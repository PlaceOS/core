require "placeos-driver/protocol/management"
require "redis-cluster"

require "../process_manager"
require "./common"
require "../edge_error"
require "../../placeos-edge/transport"
require "../../placeos-edge/protocol"

module PlaceOS::Core
  class ProcessManager::Edge
    include ProcessManager
    include Common

    alias Transport = PlaceOS::Edge::Transport
    alias Protocol = PlaceOS::Edge::Protocol

    getter transport : Transport
    getter edge_id : String

    protected getter(store : DriverStore) { DriverStore.new }

    # Error tracking
    private getter recent_errors = Deque(EdgeError).new(100)
    private getter module_init_failures = Hash(String, Array(ModuleInitError)).new { |h, k| h[k] = [] of ModuleInitError }
    private getter connection_health : EdgeHealth
    private getter error_lock = Mutex.new
    private getter connection_start_time : Time

    def initialize(@edge_id : String, socket : HTTP::WebSocket)
      @connection_start_time = Time.utc
      @connection_health = EdgeHealth.new(@edge_id, connected: true)

      @transport = Transport.new do |(sequence_id, request)|
        if request.is_a?(Protocol::Client::Request)
          handle_request(sequence_id, request)
        else
          Log.error { {message: "unexpected edge request", request: request.to_json} }
          track_error(ErrorType::Connection, "Unexpected edge request: #{request.to_json}")
        end
      end

      spawn { transport.listen(socket) }
      Fiber.yield

      # Track successful connection
      track_connection_event(ConnectionEventType::Connected)
    end

    def handle_request(sequence_id : UInt64, request : Protocol::Client::Request)
      Log.debug { {sequence_id: sequence_id.to_s, type: request.type.to_s, message: "received request"} }

      case request
      when Protocol::Message::DebugMessage
        boolean_response(sequence_id, request) do
          forward_debug_message(request.module_id, request.message)
        end
      when Protocol::Message::FetchBinary
        response = fetch_binary(request.key)
        send_response(sequence_id, response)
      when Protocol::Message::ProxyRedis
        boolean_response(sequence_id, request) do
          on_redis(
            action: request.action,
            hash_id: request.hash_id,
            key_name: request.key_name,
            status_value: request.status_value,
          )
        end
      when Protocol::Message::Register
        register_response = register(modules: request.modules, drivers: request.drivers)
        send_response(sequence_id, register_response)
      when Protocol::Message::SettingsAction
        boolean_response(sequence_id, request) do
          on_setting(
            id: request.module_id,
            setting_name: request.setting_name,
            setting_value: YAML.parse(request.setting_value)
          )
        end
      when Protocol::Message::ErrorReport
        boolean_response(sequence_id, request) do
          # Process error reports from edge
          process_edge_error_report(request)
          true
        end
      when Protocol::Message::HealthReport
        boolean_response(sequence_id, request) do
          # Process health reports from edge
          process_edge_health_report(request)
          true
        end
      end
    rescue e
      Log.error(exception: e) { {
        message: "failed to handle edge request",
        request: request.to_json,
      } }
      track_error(ErrorType::ModuleExecution, e.message || "Unknown error", {"sequence_id" => sequence_id.to_s, "request_type" => request.type.to_s})
    end

    def execute(module_id : String, payload : String, user_id : String?)
      response = Protocol.request(Protocol::Message::Execute.new(module_id, payload, user_id), expect: Protocol::Message::ExecuteResponse, preserve_response: true)
      if response.nil?
        raise PlaceOS::Driver::RemoteException.new("No response received from edge received", IO::TimeoutError.class.to_s)
      elsif !response.success
        output = response.output
        if output
          error = NamedTuple(message: String, backtrace: Array(String), code: Int32?).from_json(output)
          backtrace = error[:backtrace]
          error_code = error[:code]
          message, error_class = ProcessManager::Edge.extract_remote_error_class(error[:message])
        end

        raise PlaceOS::Driver::RemoteException.new(message, error_class, backtrace || [] of String, error_code || 500)
      else
        {response.output, response.code || 200}
      end
    end

    def load(module_id : String, driver_key : String)
      success = !!Protocol.request(Protocol::Message::Load.new(module_id, ProcessManager.path_to_key(driver_key)), expect: Protocol::Message::Success)

      unless success
        error = ModuleInitError.new(module_id, driver_key, "Failed to load module")
        track_module_init_error(error)
        track_error(ErrorType::ModuleInit, "Failed to load module #{module_id}", {"driver_key" => driver_key})
      end

      success
    rescue e
      track_error(ErrorType::DriverLoad, "Exception during module load: #{e.message}", {"module_id" => module_id, "driver_key" => driver_key})
      false
    end

    def unload(module_id : String)
      !!Protocol.request(Protocol::Message::Unload.new(module_id), expect: Protocol::Message::Success)
    end

    def start(module_id : String, payload : String)
      success = !!Protocol.request(Protocol::Message::Start.new(module_id, payload), expect: Protocol::Message::Success)

      unless success
        driver_key = driver_key_for?(module_id) || "unknown"
        error = ModuleInitError.new(module_id, driver_key, "Failed to start module")
        track_module_init_error(error)
        track_error(ErrorType::ModuleInit, "Failed to start module #{module_id}", {"driver_key" => driver_key})
      end

      success
    rescue e
      track_error(ErrorType::ModuleInit, "Exception during module start: #{e.message}", {"module_id" => module_id})
      false
    end

    def stop(module_id : String)
      !!Protocol.request(Protocol::Message::Stop.new(module_id), expect: Protocol::Message::Success)
    end

    def kill(driver_key : String)
      !!Protocol.request(Protocol::Message::Kill.new(ProcessManager.path_to_key(driver_key)), expect: Protocol::Message::Success)
    end

    alias Module = Protocol::Message::RegisterResponse::Module

    # Calculates the modules/drivers that the edge needs to add/remove
    #
    protected def register(drivers : Set(String), modules : Set(String))
      allocated_drivers = Set(String).new
      allocated_modules = Set(Module).new
      edge_modules = {} of String => PlaceOS::Model::Module

      PlaceOS::Model::Module.on_edge(edge_id).each do |mod|
        driver = mod.driver.not_nil!
        mod_id = mod.id.as(String)
        edge_modules[mod_id] = mod
        driver_path = store.built?(driver.file_name, driver.commit, driver.repository!.branch, driver.repository!.uri)
        if driver_path
          driver_key = Path[driver_path].basename
          allocated_modules << {key: driver_key, module_id: mod_id}
          allocated_drivers << driver_key
        else
          Log.error { {message: "Executable for #{driver.id} not present", driver: driver.id, commit: driver.commit} }
        end
      end

      add_modules = allocated_modules.reject { |mod| modules.includes?(mod[:module_id]) }
      remove_modules = (modules - allocated_modules.map(&.[:module_id])).to_a

      # After registering the modules we need to start them
      should_start = [] of Tuple(String, String)
      add_modules.each do |module_details|
        module_id = module_details[:module_id]
        mod = edge_modules[module_id]
        next unless mod.running
        should_start << {module_id, ModuleManager.start_payload(mod)}
      end

      Protocol::Message::RegisterResponse.new(
        success: true,
        add_drivers: (allocated_drivers - drivers).to_a,
        remove_drivers: (drivers - allocated_drivers).to_a,
        add_modules: add_modules,
        remove_modules: remove_modules,
        running_modules: should_start
      )
    end

    # Callbacks
    ###############################################################################################

    private getter debug_lock : Mutex { Mutex.new }
    private getter debug_callbacks = Hash(String, Array(DebugCallback)).new { |h, k| h[k] = [] of DebugCallback }

    def forward_debug_message(module_id : String, message : String)
      debug_lock.synchronize do
        debug_callbacks[module_id].each &.call(message)
      end
    end

    def debug(module_id : String, &on_message : DebugCallback)
      signal = debug_lock.synchronize do
        callbacks = debug_callbacks[module_id]
        callbacks << on_message
        callbacks.size == 1
      end

      send_request(Protocol::Message::Debug.new(module_id)) if signal
    end

    def ignore(module_id : String, &on_message : DebugCallback)
      signal = debug_lock.synchronize do
        module_callbacks = debug_callbacks[module_id]
        initial_size = module_callbacks.size
        module_callbacks.reject! on_message

        # Only signal if the module was still in the process of debugging
        if module_callbacks.empty?
          debug_callbacks.delete(module_id)
          initial_size > 0
        else
          false
        end
      end

      send_request(Protocol::Message::Ignore.new(module_id)) if signal
    end

    # Remove all debug listeners on a module, returning the debug callback array
    #
    def ignore(module_id : String) : Array(DebugCallback)
      debug_lock.synchronize do
        debug_callbacks[module_id].dup.tap do |callbacks|
          callbacks.each do |callback|
            ignore(module_id, &callback)
          end
        end
      end
    end

    def on_exec(request : Request, response_callback : Request ->)
      {{ raise "Edge modules cannot make execute requests" }}
    end

    def on_system_model(request : Request, response_callback : Request ->)
      {{ raise "Edge modules cannot request control systems" }}
    end

    def on_redis(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?)
      Driver::RedisStorage.with_redis do |redis|
        case action
        in .hset?
          value = status_value || "null"
          redis.pipelined(key: hash_id, reconnect: true) do |pipeline|
            pipeline.hset(hash_id, key_name, value)
            pipeline.publish("#{hash_id}/#{key_name}", value)
          end
        in .set?
          # Note:
          # - Driver sends `key` in `hash_id` position
          # - Driver sends `value` in `key_name` position
          redis.set(hash_id, key_name)
        in .publish?
          # Note:
          # - Driver sends `channel` in `hash_id` position
          # - Driver sends `value` in `key_name` position
          redis.publish(hash_id, key_name)
        in .clear?
          keys = redis.hkeys(hash_id)
          redis.pipelined(key: hash_id, reconnect: true) do |pipeline|
            keys.each do |key|
              pipeline.hdel(hash_id, key)
              pipeline.publish("#{hash_id}/#{key}", "null")
            end
          end
        end
      end
    end

    # Binaries
    ###############################################################################################

    def fetch_binary(driver_key : String) : Protocol::Message::BinaryBody
      path = store.path(driver_key).to_s
      Protocol::Message::BinaryBody.new(success: File.exists?(path), key: driver_key, path: path)
    end

    # Metadata
    ###############################################################################################

    def driver_loaded?(driver_key : String) : Bool
      !!Protocol.request(Protocol::Message::DriverLoaded.new(ProcessManager.path_to_key(driver_key)), expect: Protocol::Message::Success)
    end

    def module_loaded?(module_id : String) : Bool
      !!Protocol.request(Protocol::Message::ModuleLoaded.new(module_id), expect: Protocol::Message::Success)
    end

    def run_count : Count
      response = Protocol.request(Protocol::Message::RunCount.new, expect: Protocol::Message::RunCountResponse)
      raise "failed to request run count" if response.nil?

      response.count
    end

    def loaded_modules
      response = Protocol.request(Protocol::Message::LoadedModules.new, expect: Protocol::Message::LoadedModulesResponse)

      raise "failed to request loaded modules " if response.nil?

      response.modules
    end

    def system_status : SystemStatus
      response = Protocol.request(Protocol::Message::SystemStatus.new, expect: Protocol::Message::SystemStatusResponse)

      raise "failed to request edge system status" if response.nil?

      response.status
    end

    def driver_status(driver_key : String) : DriverStatus?
      response = Protocol.request(Protocol::Message::DriverStatus.new(ProcessManager.path_to_key(driver_key)), expect: Protocol::Message::DriverStatusResponse)

      Log.warn { {message: "failed to request driver status", driver_key: driver_key} } if response.nil?

      response.try &.status
    end

    protected def boolean_response(sequence_id, request, &)
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

    protected def send_response(sequence_id : UInt64, response : Protocol::Server::Response | Protocol::Message::BinaryBody | Protocol::Message::Success)
      t = transport
      raise "cannot send response over closed transport" if t.nil?
      t.send_response(sequence_id, response)
    end

    protected def send_request(request : Protocol::Server::Request)
      t = transport
      raise "cannot send request over closed transport" if t.nil?
      t.send_request(request)
    end

    # Utilities
    ###############################################################################################

    # Uses a `Regex` to extract the remote exception.
    def self.extract_remote_error_class(message : String) : {String, String}
      match = message.match(/\((.*?)\)$/)
      exception = match.try &.captures.first || "Exception"
      message = match.pre_match unless match.nil?
      {message, exception}
    end

    # Error Tracking Methods
    ###############################################################################################

    # Track an error for this edge
    def track_error(type : ErrorType, message : String, context = {} of String => String, severity = Severity::Error)
      error = EdgeError.new(@edge_id, type, message, context, severity)

      error_lock.synchronize do
        recent_errors.push(error)
        recent_errors.shift if recent_errors.size > 100

        # Update health metrics
        @connection_health = @connection_health.copy_with(
          error_count_24h: @connection_health.error_count_24h + 1,
          last_seen: Time.utc
        )
      end

      Log.warn { {
        edge_id:    @edge_id,
        error_type: type.to_s,
        severity:   severity.to_s,
        message:    message,
        context:    context.to_json,
      } }
    end

    # Track module initialization errors
    def track_module_init_error(error : ModuleInitError)
      error_lock.synchronize do
        module_init_failures[error.module_id] << error

        # Keep only last 10 errors per module
        if module_init_failures[error.module_id].size > 10
          module_init_failures[error.module_id].shift
        end

        # Update failed modules list
        failed_modules = @connection_health.failed_modules.dup
        failed_modules << error.module_id unless failed_modules.includes?(error.module_id)

        @connection_health = @connection_health.copy_with(
          failed_modules: failed_modules,
          last_seen: Time.utc
        )
      end
    end

    # Track connection events
    def track_connection_event(event_type : ConnectionEventType, error_message : String? = nil)
      duration = case event_type
                 when .connected?, .reconnected?
                   nil
                 when .disconnected?, .failed?
                   Time.utc - @connection_start_time
                 else
                   nil
                 end

      case event_type
      when .connected?, .reconnected?
        error_lock.synchronize do
          @connection_health = @connection_health.copy_with(
            connected: true,
            last_seen: Time.utc,
            connection_uptime: Time.utc - @connection_start_time
          )
        end
      when .disconnected?, .failed?
        error_lock.synchronize do
          @connection_health = @connection_health.copy_with(
            connected: false,
            last_seen: Time.utc
          )
        end

        if event_type.failed?
          track_error(ErrorType::Connection, error_message || "Connection failed", severity: Severity::Critical)
        end
      end
    end

    # Get recent errors for this edge
    def get_recent_errors(limit : Int32 = 50) : Array(EdgeError)
      error_lock.synchronize do
        errors = recent_errors.to_a
        if errors.size > limit
          errors[-limit..-1]
        else
          errors
        end
      end
    end

    # Get module initialization failures
    def get_module_init_failures : Hash(String, Array(ModuleInitError))
      error_lock.synchronize do
        module_init_failures.dup
      end
    end

    # Get edge health status
    def get_edge_health : EdgeHealth
      error_lock.synchronize do
        # Update module count
        module_count = get_module_managers.size
        @connection_health = @connection_health.copy_with(
          module_count: module_count,
          last_seen: Time.utc,
          connection_uptime: @connection_health.connected ? Time.utc - @connection_start_time : @connection_health.connection_uptime
        )
        @connection_health
      end
    end

    # Get edge module status
    def get_edge_module_status : EdgeModuleStatus
      error_lock.synchronize do
        managers = get_module_managers
        total_modules = managers.size

        # Count running modules (simplified - assumes loaded = running)
        running_modules = managers.count { |_, manager| manager.running? rescue false }

        failed_modules = @connection_health.failed_modules.dup
        init_errors = module_init_failures.values.flatten

        EdgeModuleStatus.new(@edge_id, total_modules, running_modules, failed_modules, init_errors)
      end
    end

    # Clear old errors (called periodically)
    def cleanup_old_errors(older_than : Time::Span = 24.hours)
      cutoff_time = Time.utc - older_than

      error_lock.synchronize do
        # Remove old errors
        recent_errors.reject! { |error| error.timestamp < cutoff_time }

        # Reset 24h error count
        @connection_health = @connection_health.copy_with(
          error_count_24h: recent_errors.count { |error| error.timestamp > cutoff_time }
        )

        # Clean up old module init failures
        module_init_failures.each do |module_id, errors|
          errors.reject! { |error| error.timestamp < cutoff_time }
          module_init_failures.delete(module_id) if errors.empty?
        end
      end
    end

    # Protocol message handlers
    ###############################################################################################

    private def process_edge_error_report(request : Protocol::Message::ErrorReport)
      Log.info { {message: "processing error report from edge", edge_id: request.edge_id, error_count: request.errors.size} }

      error_lock.synchronize do
        request.errors.each do |error_json|
          begin
            # Parse the JSON serialized EdgeError
            edge_error = EdgeError.from_json(error_json)

            # Ensure the edge_id matches
            if edge_error.edge_id == @edge_id
              # Add to recent errors (bounded deque will automatically remove old ones)
              recent_errors.push(edge_error)

              # Update connection health error count
              cutoff_time = Time.utc - 24.hours
              @connection_health = @connection_health.copy_with(
                error_count_24h: recent_errors.count { |e| e.timestamp > cutoff_time },
                last_seen: Time.utc
              )

              Log.debug { {message: "stored edge error", edge_id: @edge_id, error_type: edge_error.error_type.to_s, severity: edge_error.severity.to_s} }
            else
              Log.warn { {message: "edge error report edge_id mismatch", expected: @edge_id, received: edge_error.edge_id} }
            end
          rescue ex : JSON::ParseException
            Log.error(exception: ex) { {message: "failed to parse edge error from JSON", error_json: error_json} }
            track_error(ErrorType::Connection, "Failed to parse edge error report: #{ex.message}")
          end
        end
      end
    end

    private def process_edge_health_report(request : Protocol::Message::HealthReport)
      Log.info { {message: "processing health report from edge", edge_id: request.edge_id} }

      begin
        # Parse the JSON serialized EdgeHealth
        edge_health = EdgeHealth.from_json(request.health)

        # Ensure the edge_id matches
        if edge_health.edge_id == @edge_id
          error_lock.synchronize do
            # Update our connection health with data from edge
            @connection_health = @connection_health.copy_with(
              connected: edge_health.connected,
              last_seen: Time.utc,
              module_count: edge_health.module_count,
              failed_modules: edge_health.failed_modules,
              # Keep our own connection_uptime calculation
              connection_uptime: Time.utc - @connection_start_time
            )
          end

          Log.debug { {message: "updated edge health", edge_id: @edge_id, module_count: edge_health.module_count, failed_modules: edge_health.failed_modules.size} }
        else
          Log.warn { {message: "edge health report edge_id mismatch", expected: @edge_id, received: edge_health.edge_id} }
        end
      rescue ex : JSON::ParseException
        Log.error(exception: ex) { {message: "failed to parse edge health from JSON", health_json: request.health} }
        track_error(ErrorType::Connection, "Failed to parse edge health report: #{ex.message}")
      end
    end
  end
end
