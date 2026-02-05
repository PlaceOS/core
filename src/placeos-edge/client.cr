require "simple_retry"
require "rwlock"
require "uri"

require "placeos-driver/protocol/management"

require "../placeos-core/process_manager/common"
require "../placeos-core/driver_manager"

require "./constants"
require "./protocol"
require "./transport"

module PlaceOS::Edge
  class Client
    include Core::ProcessManager::Common

    Log                = ::Log.for(self)
    WEBSOCKET_API_PATH = "/api/engine/v2/edges/control"

    protected getter store : Core::DriverStore

    private getter secret : String

    private getter! uri : URI
    protected getter! transport : Transport

    # NOTE: For testing purposes
    private getter? skip_handshake : Bool
    private getter? ping : Bool

    private getter close_channel = Channel(Nil).new

    # structures for tracking what has been loaded and what has been requested
    # this allows us do some of these things out of order when they become available
    @loading_mutex = Mutex.new(:reentrant)
    # driver_key => downloaded signal
    @loading_driver_keys = {} of String => Channel(Nil)
    # driver_key => [mod_ids]
    @loading_modules = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
    # module_id => payload
    @pending_start = {} of String => String

    getter host : String { uri.to_s.gsub(uri.request_target, "") }

    def initialize(
      uri : URI = PLACE_URI,
      secret : String? = nil,
      @sequence_id : UInt64 = 0,
      @skip_handshake : Bool = false,
      @ping : Bool = true,
      @store = Core::DriverStore.new,
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

    alias ModuleError = ::PlaceOS::Core::ModuleError

    # Implement the abstract method from Common
    def execute(module_id : String, payload : String | IO, user_id : String?, mod : Model::Module? = nil)
      manager = protocol_manager_by_module?(module_id)

      raise ModuleError.new("No protocol manager for #{module_id}") if manager.nil?

      request_body = payload.is_a?(IO) ? payload.gets_to_end : payload
      manager.execute(
        module_id,
        request_body,
        user_id: user_id,
      )
    rescue error : PlaceOS::Driver::RemoteException
      raise error
    rescue exception
      raise module_error(module_id, exception)
    end

    # Initialize the WebSocket API
    #
    # Optionally accepts a block called after connection has been established.
    def connect(initial_socket : HTTP::WebSocket? = nil, &)
      Log.info { "connecting to #{host}" }

      @transport = Transport.new(
        on_disconnect: ->(_error : HTTP::WebSocket::CloseCode | IO::Error) {
          Log.debug { "core connection lost. Cleaning up pending operations" }

          @loading_mutex.synchronize do
            @loading_driver_keys.each { |_driver_key, channel| channel.close }
            @loading_driver_keys = {} of String => Channel(Nil)
            @loading_modules = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
            @pending_start = {} of String => String
          end
          nil
        },
        on_connect: -> {
          handshake unless skip_handshake?
          nil
        }
      ) do |(sequence_id, request)|
        if request.is_a?(Protocol::Server::Request)
          handle_request(sequence_id, request)
        else
          Log.error { {message: "unexpected core request", request: request.to_json} }
        end
      end

      spawn { transport.connect(uri, initial_socket) }

      while transport.closed?
        sleep 10.milliseconds
        Fiber.yield
      end

      # Send ping frames
      spawn { transport.ping if ping? }

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
          driver_loaded?(request.driver_key)
        end
      in Protocol::Message::DriverStatus
        status = driver_status(request.driver_key)
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
          # @loading_mutex.synchronize do
          #   File.delete(path(request.driver_key)) if !protocol_manager_by_driver?(request.driver_key) && File.exists?(path(request.driver_key))
          # end
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
          queue_start(request.module_id, request.payload)
        end
      in Protocol::Message::Stop
        boolean_command(sequence_id, request) do
          @loading_mutex.synchronize do
            @pending_start.delete(request.module_id)
            stop(request.module_id)
          end
        end
      in Protocol::Message::SystemStatus
        send_response(sequence_id, Protocol::Message::SystemStatusResponse.new(system_status))
      in Protocol::Message::Unload
        boolean_command(sequence_id, request) do
          @loading_mutex.synchronize do
            @pending_start.delete(request.module_id)
            if driver_key = driver_key_for?(request.module_id)
              if modules = @loading_modules[driver_key]?
                modules.delete(request.module_id)
                if modules.empty? && (channel = @loading_driver_keys.delete(driver_key))
                  # abort downloading of driver
                  channel.close
                end
              end
            end
            unload(request.module_id)
          end
        end
      in Protocol::Message::Body
        Log.warn { {message: "unexpected message in handle request", type: request.type.to_s} }
      end
    rescue e
      Log.error(exception: e) { {message: "failed to handle core request", request: request.to_json} }
    end

    def handshake
      SimpleRetry.try_to(base_interval: 500.milliseconds, max_interval: 5.seconds) do
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

          response.running_modules.each do |(module_id, payload)|
            queue_start(module_id, payload)
          end

          Log.info { "handshake success, edge registered" }
        rescue error
          Log.error(exception: error) { "during handshake" }
          raise error
        end
      end
    end

    def queue_start(module_id : String, payload : String)
      @loading_mutex.synchronize do
        if protocol_manager_by_module?(module_id)
          start(module_id, payload)
        else
          @pending_start[module_id] = payload
        end
      end
    end

    # Kicks off downloading all the binaries
    def load_binaries(binaries : Array(String))
      promises = binaries.map do |driver_key|
        File.delete(path(driver_key)) if File.exists?(path(driver_key))
        Promise.defer do
          if wait_load = load_binary(driver_key)
            select
            when wait_load.receive?
            when timeout(90.seconds)
              Log.error { "timeout loading #{driver_key}" }
            end
          end
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
      store.compiled_drivers.to_set
    end

    # Load binary, first checking if present locally then fetch from core
    #
    def load_binary(key : String) : Channel(Nil)?
      perform_load = true
      loaded_channel = Channel(Nil).new

      @loading_mutex.synchronize do
        Log.debug { {key: key, message: "loading binary"} }

        if loading = @loading_driver_keys[key]?
          perform_load = false
          loaded_channel = loading
        else
          return if File.exists?(path(key))
          @loading_driver_keys[key] = loaded_channel
        end
      end

      return loaded_channel unless perform_load
      spawn { attempt_download(loaded_channel, key) }

      loaded_channel
    end

    def attempt_download(loaded_channel, key)
      binary = SimpleRetry.try_to(base_interval: 5.seconds, max_interval: 30.seconds) do
        result = fetch_binary(key) unless loaded_channel.closed?
        raise "retry" if result.nil? && !loaded_channel.closed? && @loading_driver_keys[key]? == loaded_channel
        result
      end

      @loading_mutex.synchronize do
        if !loaded_channel.closed?
          # write the executable
          if binary
            add_binary(key, binary)
          end

          # signal that we're ready to run
          loaded_channel.close
          @loading_driver_keys.delete(key)

          # load any requests that have come in the mean time
          if pending = @loading_modules.delete(key)
            pending.each do |module_id|
              load(module_id, key)
              if payload = @pending_start.delete(module_id)
                start(module_id, payload)
              end
            end
          end
        end
      end
    rescue error
      Log.error(exception: error) { "error during download attempt" }
      spawn { attempt_download(loaded_channel, key) } unless loaded_channel.closed?
    end

    def fetch_binary(key : String) : IO?
      response = Protocol.request(Protocol::Message::FetchBinary.new(key), expect: Protocol::Message::BinaryBody)
      response.try &.io
    end

    def add_binary(key : String, binary : IO)
      path = path(key)
      File.delete(path) if File.exists?(path)
      Log.debug { {path: path, message: "writing binary"} }

      # Default permissions + execute for owner
      File.open(path, mode: "w+", perm: File::Permissions.new(0o744)) do |file|
        IO.copy(binary, file)
      end
    end

    def remove_binary(key : String)
      @loading_mutex.synchronize do
        # clean up any pending operations
        if loading = @loading_driver_keys.delete(key)
          loading.close
        end
        if pending = @loading_modules.delete(key)
          pending.each { |module_id| @pending_start.delete(module_id) }
        end
        File.delete(path(key))
      end
      true
    rescue
      false
    end

    protected def path(key : String)
      store.path(key).to_s
    end

    # Modules
    ###########################################################################

    # Check for binary, request if it's not present
    # Start the module with redis hooks
    def load(module_id, driver_key)
      Log.context.set(module_id: module_id, driver_key: driver_key)

      if !protocol_manager_by_module?(module_id)
        if existing_driver_manager = protocol_manager_by_driver?(driver_key)
          # Use the existing driver protocol manager
          set_module_protocol_manager(module_id, existing_driver_manager)
        else
          if wait_load = load_binary(driver_key)
            select
            when wait_load.receive?
              @loading_mutex.synchronize do
                unless File.exists?(path(driver_key))
                  Log.info { "module load aborted" }
                  return
                end
              end
            when timeout(20.seconds)
              @loading_mutex.synchronize do
                # ensure we are still loading this
                if @loading_driver_keys[driver_key]?
                  @loading_modules[driver_key] << module_id
                  Log.info { "queuing module load" }
                  return
                end
              end
            end
          end

          # Create a new protocol manager
          manager = Driver::Protocol::Management.new(path(driver_key), on_edge: true)

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
    protected def boolean_command(sequence_id, request, &)
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
