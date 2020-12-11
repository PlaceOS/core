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
    WEBSOCKET_API_PATH = "/api/engine/v2/edges/control"

    class_property binary_directory : String = File.join(Dir.current, "/bin/drivers")

    getter edge_id : String
    private getter secret : String

    private getter transport : Transport?
    private getter! uri : URI

    # NOTE: For testing
    private getter? skip_handshake : Bool

    private getter close_channel = Channel(Nil).new

    def self.extract_token(token : String)
      parts = token.split('_')
      raise "Invalid token: #{token}" unless parts.size == 2
      edge_id, secret = parts
      ({edge_id, secret})
    end

    def self.create_token(edge_id : String, secret : String)
      Base64.urlsafe_encode("#{edge_id}_#{secret}")
    end

    def host
      uri.to_s.gsub(uri.full_path, "")
    end

    def initialize(
      uri : URI = PLACE_URI,
      edge_id : String? = nil,
      secret : String? = nil,
      @sequence_id : UInt64 = 0,
      @skip_handshake : Bool = false
    )
      if secret && edge_id && secret.presence && edge_id.presence
        @edge_id = edge_id
        @secret = secret
      else
        Log.info { "using secret from environment" }
        id, secret = Client.extract_token(CLIENT_SECRET) rescue abort("Invalid secret: #{CLIENT_SECRET}")
        @edge_id, @secret = id, secret
      end

      # Mutate a copy as secret is embedded in uri
      uri = uri.dup
      uri.path = WEBSOCKET_API_PATH
      uri.query = "token=#{Client.create_token(@edge_id, @secret)}"
      @uri = uri
    end

    # Initialize the WebSocket API
    #
    # Optionally accepts a block called after connection has been established.
    def connect(initial_socket : HTTP::WebSocket? = nil)
      initial = initial_socket
      Log.context.set(edge_id: edge_id)
      Log.info { "connecting to #{host}" }
      Retriable.retry(max_interval: 5.seconds, on_retry: ->(error : Exception, _i : Int32, _e : Time::Span, _p : Time::Span) {
        Log.warn { {error: error.to_s, message: "reconnecting"} }
        initial = nil
      }) do
        socket = (initial || HTTP::WebSocket.new(uri)).as(HTTP::WebSocket)
        socket.on_close do |code, _message|
          case code
          when .normal_closure?
            Log.info { "websocket to #{host} closed" }
          when .abnormal_closure?
            # TODO: close off all debug streams to modules
          end
        end

        id = if existing_transport = transport
               existing_transport.sequence_id
             else
               0_u64
             end

        @transport = Transport.new(socket, id) do |(sequence_id, request)|
          if request.is_a?(Protocol::Server::Request)
            handle_request(sequence_id, request)
          else
            Log.error { {message: "unexpected core request", request: request.to_json} }
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

    def disconnect
      close_channel.close
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def handle_request(sequence_id : UInt64, request : Protocol::Server::Request)
      case request
      in Protocol::Message::Debug
        boolean_command(sequence_id, request) do
          debug(request.module_id)
        end
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
      in Protocol::Message::Ignore
        boolean_command(sequence_id, request) do
          ignore(request.module_id)
        end
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
        send_response(sequence_id, run_count_message)
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
        Log.warn { {message: "unexpected message in handle request", type: request.type.to_s} }
      end
    rescue e
      Log.error(exception: e) { {message: "failed to handle core request", request: request.to_json} }
    end

    def handshake
      Retriable.retry do
        begin
          response = Protocol.request(registration_message, expect: Protocol::Message::RegisterResponse)
          unless response
            Log.warn { "failed to register to core" }
            raise "handshake failed"
          end

          response.remove_modules.each do |mod|
            unload(mod)
          end

          response.remove_drivers.each do |driver|
            remove_binary(driver)
          end

          load_binaries(response.add_drivers)

          response.add_modules.each do |mod|
            load(mod[:module_id], mod[:key])
          end
        rescue error
          Log.error(exception: error) { "during handshake" }
          raise error
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
        drivers: drivers,
      )
    end

    protected def run_count_message : Protocol::Message::RunCountResponse
      Protocol::Message::RunCountResponse.new(count: run_count)
    end

    # Driver binaries
    ###########################################################################

    # List the driver binaries present on this client
    #
    def drivers
      Dir.mkdir_p(self.class.binary_directory) unless Dir.exists?(self.class.binary_directory)
      Dir.children(self.class.binary_directory).reject do |file|
        file.includes?(".") || File.directory?(file)
      end.to_set
    end

    # Load binary, first checking if present locally then fetch from core
    #
    def load_binary(key : String) : Bool
      return true if File.exists?(path(key))

      binary = begin
        Retriable.retry(max_attempts: 5, base_interval: 5.seconds) do
          result = fetch_binary(key)
          raise "retry" if result.nil?
          result
        end
      rescue e
        Log.error(exception: e) { "while fetching binary" } unless e.message == "retry"
        nil
      end

      add_binary(key, binary) if binary

      !binary.nil?
    end

    def fetch_binary(key : String) : Bytes?
      response = Protocol.request(Protocol::Message::FetchBinary.new(key), expect: Protocol::Message::BinaryBody)
      response.try &.binary
    end

    def add_binary(key : String, binary : Bytes)
      # Default permissions + execute for owner
      File.open(path(key), mode: "w+", perm: 0o744) do |file|
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
      File.join(self.class.binary_directory, key)
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
          manager = Driver::Protocol::Management.new(path(driver_key), on_edge: true)

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
        @module_proc_managers.keys.to_set
      end
    end

    # Debugging
    ###########################################################################

    private getter debug_callbacks = {} of String => String -> Nil
    private getter debug_lock = Mutex.new(protection: :reentrant)

    def debug(module_id : String)
      debug_lock.synchronize do
        unless debug_callbacks.has_key?(module_id)
          callback = ->(message : String) { forward_debug_message(module_id, message); nil }
          debug_callbacks[module_id] = callback
          proc_manager_by_module?(module_id).try &.debug(module_id, &callback)
        end
      end
    end

    def ignore(module_id : String)
      debug_lock.synchronize do
        callback = debug_callbacks.delete(module_id)
        proc_manager_by_module?(module_id).try &.ignore(module_id, &callback) unless callback.nil?
      end
    end

    def forward_debug_message(module_id, message)
      send_request(Protocol::Message::DebugMessage.new(module_id, message))
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

      Protocol.request(request, expect: Protocol::Message::Success)
    end

    # Proxy a redis action via Core
    def on_redis(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?)
      request = Protocol::Message::ProxyRedis.new(
        action: action,
        hash_id: hash_id,
        key_name: key_name,
        status_value: status_value,
      )

      Protocol.request(request, expect: Protocol::Message::Success)
    end

    # Transport
    ###########################################################################

    # Bundles up the result of a command into a `Success` response
    #
    protected def boolean_command(sequence_id, request)
      success = begin
        result = yield
        result.is_a?(Bool) ? result : true
      rescue e
        meta = request.responds_to?(:module_id) ? request.module_id : (request.responds_to?(:driver_key) ? request.driver_key : nil)
        Log.error(exception: e) { "failed to #{request.type.to_s.underscore} #{meta}" }
        false
      end
      send_response(sequence_id, Protocol::Message::Success.new(success))
    end

    protected def send_response(sequence_id : UInt64, response : Protocol::Client::Response | Protocol::Message::Success)
      t = transport
      raise "cannot send response over closed transport" if t.nil?
      t.send_response(sequence_id, response)
    end

    protected def send_request(request : Protocol::Client::Request)
      t = transport
      raise "cannot send request over closed transport" if t.nil?
      t.send_request(request)
    end
  end
end
