require "retriable"
require "rwlock"
require "uri"
require "file_utils"

require "placeos-driver/protocol/management"

require "../placeos-core/process_manager/common"
require "placeos-build/driver_store/filesystem"

require "./constants"
require "./protocol"
require "./transport"

module PlaceOS::Edge
  class Client
    include Core::ProcessManager::Common

    Log                = ::Log.for(self)
    WEBSOCKET_API_PATH = "/api/engine/v2/edges/control"

    private getter secret : String

    private getter! uri : URI
    getter host : String { uri.to_s.gsub(uri.request_target, "") }

    protected getter! transport : Transport

    # NOTE: For testing purposes
    private getter? skip_handshake : Bool
    private getter? ping : Bool

    private getter close_channel = Channel(Nil).new

    getter binary_store : Build::Filesystem

    def initialize(
      uri : URI = PLACE_URI,
      secret : String? = nil,
      @sequence_id : UInt64 = 0,
      @skip_handshake : Bool = false,
      @ping : Bool = true,
      @binary_store : Build::Filesystem = Build::Filesystem.new
    )
      @secret = if secret && secret.presence
                  secret
                else
                  Log.info { "using PLACE_EDGE_KEY from environment" }
                  CLIENT_SECRET
                end

      # Mutate a copy as secret is embedded in uri
      uri = uri.dup
      uri.path = WEBSOCKET_API_PATH
      uri.query = "api-key=#{@secret}"
      @uri = uri
    end

    # Initialize the WebSocket API
    #
    # Optionally accepts a block called after connection has been established.
    def connect(initial_socket : HTTP::WebSocket? = nil)
      Log.info { "connecting to #{host}" }

      @transport = Transport.new do |(sequence_id, request)|
        if request.is_a?(Protocol::Server::Request)
          handle_request(sequence_id, request)
        else
          Log.error { {message: "unexpected core request", request: request.to_json} }
        end
      end

      spawn(same_thread: true) { transport.connect(uri, initial_socket) }

      while transport.closed?
        sleep 0.01
        Fiber.yield
      end

      # Send ping frames
      spawn(same_thread: true) { transport.ping if ping? }

      handshake unless skip_handshake?

      yield

      close_channel.receive?
      transport.disconnect
    end

    # :ditto:
    def connect(initial_socket : HTTP::WebSocket? = nil)
      connect(initial_socket) { }
    end

    def disconnect
      close_channel.close
    end

    def handle_request(sequence_id : UInt64, request : Protocol::Server::Request)
      Log.debug { {sequence_id: sequence_id.to_s, type: request.type.to_s, message: "received request"} }

      case request
      in Protocol::Message::Debug
        boolean_command(sequence_id, request) do
          debug(request.module_id)
        end
      in Protocol::Message::DriverLoaded
        boolean_command(sequence_id, request) do
          driver_loaded?(request.driver_key, request.driver_id)
        end
      in Protocol::Message::DriverStatus
        status = driver_status(request.driver_key, request.driver_id)
        send_response(sequence_id, Protocol::Message::DriverStatusResponse.new(status))
      in Protocol::Message::Execute
        success, output, response_code = begin
          result = execute(
            request.module_id,
            request.payload,
            user_id: request.user_id,
          )

          ({true, result[0], result[1]})
        rescue error : PlaceOS::Driver::RemoteException
          Log.error(exception: error) { {
            module_id: request.module_id,
            message:   "execute errored",
          } }
          ({false, {message: error.message, backtrace: error.backtrace?, code: error.code}.to_json, error.code})
        end

        send_response(sequence_id, Protocol::Message::ExecuteResponse.new(success, output, response_code))
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
          load(request.module_id, request.driver_key, request.driver_id)
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
      Retriable.retry(max_interval: 5.seconds) do
        begin
          response = Protocol.request(registration_message, expect: Protocol::Message::RegisterResponse)

          raise "failed to register to core" if response.nil?

          response.remove_modules.each do |mod|
            unload(mod)
          end

          response.remove_drivers.each do |driver|
            remove_binary(driver)
          end

          load_binaries(response.add_drivers)

          response.add_modules.each do |mod|
            load(mod.module_id, mod.key, mod.driver_id)
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
    def drivers : Set(String)
      binary_store.query.map(&.filename).to_set
    end

    # Load binary, first checking if present locally then fetch from core
    #
    def load_binary(key : String) : Bool
      executable = Model::Executable.new(key)
      Log.debug { {path: executable.filename, message: "loading binary"} }

      if binary_store.exists?(executable)
        Log.debug { {path: executable.filename, message: "binary already present"} }
        return true
      end

      binary = begin
        Retriable.retry(max_elapsed_time: 2.minutes, base_interval: 5.seconds) do
          raise "retry" unless result = fetch_binary(key)
          result
        end
      rescue e
        Log.error(exception: e) { "while fetching binary for #{key}" } unless e.message == "retry"
        nil
      end

      add_binary(key, binary) unless binary.nil?

      !binary.nil?
    end

    def fetch_binary(key : String) : IO?
      response = Protocol.request(Protocol::Message::FetchBinary.new(key), expect: Protocol::Message::BinaryBody)
      response.try &.io
    end

    def add_binary(key : String, binary : IO)
      executable = Model::Executable.new(key)

      if binary_store.exists?(executable)
        Log.debug { {path: executable.filename, message: "binary already present"} }
        return true
      end

      Log.debug { {path: executable.filename, message: "writing binary"} }

      binary_store.write(key, binary)
    end

    def remove_binary(driver_key : String)
      File.delete(binary_store.path(Model::Executable.new(driver_key)))
      true
    rescue
      false
    end

    # Modules
    ###########################################################################

    # Check for binary, request if it's not present
    # Start the module with redis hooks
    def load(module_id, driver_key, driver_id)
      Log.context.set(module_id: module_id, driver_key: driver_key)

      driver_scoped_name = Core::ProcessManager.driver_scoped_name(driver_key, driver_id)

      if !protocol_manager_by_module?(module_id)
        if (existing_driver_manager = protocol_manager_by_driver?(driver_scoped_name))
          # Use the existing driver protocol manager
          set_module_protocol_manager(module_id, existing_driver_manager)
        else
          unless load_binary(driver_key)
            Log.error { "failed to load binary for module" }
            return
          end

          executable = Model::Executable.new(driver_key)
          executable_path = binary_store.path(executable)

          driver_scoped_path = executable_path + driver_id.gsub("-", "_")

          FileUtils.cp(executable_path, driver_scoped_path)
          File.chmod(driver_scoped_path, 0o755)

          # Create a new protocol manager
          manager = Driver::Protocol::Management.new(driver_scoped_path, on_edge: true)

          # Callbacks
          manager.on_setting = ->(id : String, setting_name : String, setting_value : YAML::Any) {
            Log.debug { {module_id: module_id, driver_key: driver_key, message: "on_setting"} }
            on_setting(id, setting_name, setting_value.to_yaml)
          }

          manager.on_redis = ->(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?) {
            Log.debug { {module_id: module_id, driver_key: driver_key, action: action.to_s, message: "on_redis"} }
            on_redis(action, hash_id, key_name, status_value)
          }

          set_module_protocol_manager(module_id, manager)
          set_driver_protocol_manager(driver_key, manager)
        end

        Log.info { "module loaded" }
      else
        Log.info { "module already loaded" }
      end
    end

    # List the modules running on this client
    #
    def modules
      protocol_manager_lock.synchronize do
        @module_protocol_managers.keys.to_set
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
          protocol_manager_by_module?(module_id).try &.debug(module_id, &callback)
        end
      end
    end

    def ignore(module_id : String)
      debug_lock.synchronize do
        callback = debug_callbacks.delete(module_id)
        protocol_manager_by_module?(module_id).try &.ignore(module_id, &callback) unless callback.nil?
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
      t = transport?
      raise "cannot send response over closed transport" if t.nil?
      t.send_response(sequence_id, response)
    end

    protected def send_request(request : Protocol::Client::Request)
      t = transport?
      raise "cannot send request over closed transport" if t.nil?
      t.send_request(request)
    end
  end
end
