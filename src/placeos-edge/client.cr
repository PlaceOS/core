require "retriable"
require "rwlock"
require "uri"

require "placeos-driver/protocol/management"

require "../placeos-core/process_manager/local"

require "./constants"
require "./protocol"
require "./transport"

module PlaceOS::Edge
  class Client
    include Core::ProcessManager::Local::Common

    Log                = ::Log.for(self)
    WEBSOCKET_API_PATH = "/edge"

    getter binary_directory : String

    private getter transport : Transport?
    private getter! uri : URI

    # NOTE: For testing
    private getter? skip_handshake : Bool

    def host
      uri.to_s.gsub(uri.full_path, "")
    end

    def initialize(
      uri : URI = PLACE_URI,
      secret : String = CLIENT_SECRET,
      @sequence_id : UInt64 = 0,
      @binary_directory : String = File.join(Dir.current, "/bin/drivers"),
      @skip_handshake : Bool = false
    )
      # Mutate a copy as secret is embedded in uri
      uri = uri.dup
      uri.path = WEBSOCKET_API_PATH
      uri.query = "secret=#{secret}"
      @uri = uri
    end

    # Initialize the WebSocket API
    #
    # Optionally accepts a block called after connection has been established.
    def connect(initial_socket : HTTP::WebSocket? = nil)
      begin
        socket = initial_socket || HTTP::WebSocket.new(uri)
      rescue Socket::ConnectError
        Log.error { "failed to open initial connection to #{host}" }
        exit 1
      end

      Retriable.retry(on_retry: ->(_ex : Exception, _i : Int32, _e : Time::Span, _p : Time::Span) {
        Log.info { "reconnecting to #{host}" }
        socket = HTTP::WebSocket.new(uri)
      }) do
        close_channel = Channel(Nil).new

        socket.on_close do
          Log.info { "websocket to #{host} closed" }
          close_channel.close
        end

        id = if existing_transport = transport
               existing_transport.sequence_id
             else
               0_u64
             end

        @transport = Transport.new(socket, id) do |(sequence_id, request)|
          case request
          when Protocol::Server::Request
            handle_request(sequence_id, request.as(Protocol::Server::Request))
          else Log.error { "unexpected request received #{request.inspect}" }
          end
        end

        spawn do
          socket.as(HTTP::WebSocket).run
        end

        while socket.closed?
          Fiber.yield
        end

        handshake unless skip_handshake?

        yield

        close_channel.receive?
      end
    end

    # :ditto:
    def connect(initial_socket : HTTP::WebSocket? = nil)
      connect(initial_socket) { }
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def handle_request(sequence_id : UInt64, request : Protocol::Server::Request)
      case request
      in Protocol::Message::DriverLoaded
        boolean_command(sequence_id, request) do
          driver_loaded?(request.driver_key)
        end
      in Protocol::Message::DriverStatus
        status = driver_status(request.driver_key)
        send_response(sequence_id, Protocol::Message::DriverStatusResponse.new(status))
      in Protocol::Message::Execute
        response = Protocol::Message::ExecuteResponse.new(execute(request.module_id, request.payload))
        send_response(sequence_id, response)
      in Protocol::Message::Kill
        boolean_command(sequence_id, request) do
          kill(request.driver_key)
        end
      in Protocol::Message::Load
        boolean_command(sequence_id, request) do
          load(request.module_id, request.driver_key)
        end
      in Protocol::Message::LoadedModules
        send_response(sequence_id, Protocol::Message::LoadedModulesResponse.new(loaded_modules))
      in Protocol::Message::ModuleLoaded
        boolean_command(sequence_id, request) do
          module_loaded?(request.module_id)
        end
      in Protocol::Message::RunCount
        send_response(sequence_id, run_count)
      in Protocol::Message::Start
        boolean_command(sequence_id, request) do
          start(request.module_id, request.payload)
        end
      in Protocol::Message::Stop
        boolean_command(sequence_id, request) do
          stop(request.module_id)
        end
      in Protocol::Message::SystemStatus
        send_response(sequence_id, Protocol::Message::SystemStatusResponse.new(system_status))
      in Protocol::Message::Unload
        boolean_command(sequence_id, request) do
          unload(request.module_id)
        end
      in Protocol::Message::Body
        Log.warn { {"unexpected message in handle request: #{request.type}"} }
      end
    end

    def handshake
      Retriable.retry do
        response = send_request(registration_message)
        unless response.success && response.is_a?(Protocol::Message::RegisterResponse)
          Log.warn { "failed to register to core" }
          raise "handshake failed"
        end

        response.remove_modules.each do |mod|
          unload(mod[:module_id])
        end

        response.remove_drivers.each do |driver|
          remove_binary(driver)
        end

        load_binaries(response.add_drivers)

        response.add_modules.each do |mod|
          load(mod[:module_id], mod[:key])
        end
      end
    end

    def load_binaries(binaries : Array(String))
      promises = binaries.map do |driver_key|
        Promise.defer do
          load_binary(driver_key)
        end
      end

      Promise.all(promises).get
    end

    # Message
    ###########################################################################

    # Extracts the running modules and drivers on the edge
    #
    protected def registration_message : Protocol::Message::Register
      Protocol::Message::Register.new(
        modules: modules,
        drivers: binaries,
      )
    end

    protected def run_count : Protocol::Message::RunCountResponse
      Protocol::Message::RunCountResponse.new(
        drivers: running_drivers,
        modules: running_modules,
      )
    end

    # Bundles up the result of a command into a `Success` response
    #
    protected def boolean_command(sequence_id, request)
      success = begin
        yield
        true
      rescue e
        meta = request.responds_to?(:module_id) ? request.module_id : (request.responds_to?(:driver_key) ? request.driver_key : nil)
        Log.error(exception: e) { "failed to #{request.type.to_s.underscore} #{meta}" }
        false
      end
      send_response(sequence_id, Protocol::Message::Success.new(success))
    end

    # Driver binaries
    ###########################################################################

    # List the binaries present on this client
    #
    def binaries
      Dir.children(binary_directory).reject do |file|
        file.includes?(".") || File.directory?(file)
      end
    end

    # Load binary, first checking if present locally then fetch from core
    #
    def load_binary(key : String) : Bool
      return true if File.exists?(path(key))

      binary = fetch_binary(key)
      add_binary(key, binary) if binary

      !binary.nil?
    end

    def fetch_binary(key : String) : Bytes?
      response = send_request(Protocol::Message::FetchBinary.new(key))

      if response.is_a?(Protocol::Message::BinaryBody)
        response.binary
      else
        Log.error { {message: "fetch_binary did not receive a binary", key: key} }
        nil
      end
    end

    def add_binary(key : String, binary : Bytes)
      File.open(path(key), mode: "w+") do |file|
        file.write(binary)
      end
    end

    def remove_binary(key : String)
      File.delete(path(key))
      true
    rescue
      false
    end

    protected def path(key : String)
      File.join(binary_directory, key)
    end

    # Modules
    ###########################################################################

    # Check for binary, request if it's not present
    # Start the module with redis hooks
    def load(module_id, driver_key)
      Log.context.set({module_id: module_id, driver_key: driver_key})

      if !proc_manager_by_module?(module_id)
        if (existing_driver_manager = proc_manager_by_driver?(driver_key))
          # Use the existing driver protocol manager
          set_module_proc_manager(module_id, existing_driver_manager)
        else
          unless load_binary(driver_key)
            Log.error { "failed to load binary for module" }
            return
          end

          # Create a new protocol manager
          manager = Driver::Protocol::Management.new(driver_key, on_edge: true)

          # Callbacks

          manager.on_setting = ->(id : String, setting_name : String, setting_value : YAML::Any) {
            on_setting(id, setting_name, setting_value.to_yaml)
          }

          manager.on_redis = ->(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?) {
            on_redis(action, hash_id, key_name, status_value)
          }

          set_module_proc_manager(module_id, manager)
          set_driver_proc_manager(driver_key, manager)
        end

        Log.info { "module loaded" }
      else
        Log.info { "module already loaded" }
      end
    end

    # List the modules running on this client
    #
    def modules
      proc_manager_lock.synchronize do
        @module_proc_managers.keys
      end
    end

    # Module Callbacks
    ###########################################################################

    # Proxy a settings write via Core
    def on_setting(module_id : String, setting_name : String, setting_value : String)
      request = Protocol::Message::SettingsAction.new(
        module_id: module_id,
        setting_name: setting_name,
        setting_value: setting_value
      )

      response = send_request(request)
      unless response.is_a?(Protocol::Message::Success) && response.success
        Log.error { {module_id: module_id, setting_name: setting_name, message: "failed to proxy module setting"} }
      end
    end

    # Proxy a redis action via Core
    def on_redis(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?)
      request = Protocol::Message::ProxyRedis.new(
        action: action,
        hash_id: hash_id,
        key_name: key_name,
        status_value: status_value,
      )

      response = send_request(request)
      unless response.is_a?(Protocol::Message::Success) && response.success
        Log.error { {action: action.to_s, hash_id: hash_id, key_name: key_name, message: "failed to proxy redis action"} }
      end
    end

    # Transport
    ###########################################################################

    def send_response(sequence_id : UInt64, response : Protocol::Client::Response | Protocol::Message::Success)
      t = transport
      raise "cannot send response over closed transport" if t.nil?
      t.send_response(sequence_id, response)
    end

    def send_request(request : Protocol::Client::Request) : Protocol::Server::Response
      t = transport
      raise "cannot send request over closed transport" if t.nil?
      t.send_request(request).as(Protocol::Server::Response)
    end
  end
end
