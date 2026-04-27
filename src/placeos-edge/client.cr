require "simple_retry"
require "uri"

require "placeos-driver/protocol/management"

require "../placeos-core/driver_manager"

require "./binary_manager"
require "./constants"
require "./desired_state_client"
require "./protocol"
require "./realtime_channel"
require "./reconciler"
require "./runtime_manager"
require "./runtime_store"
require "./state"

module PlaceOS::Edge
  class Client
    Log                = ::Log.for(self)
    WEBSOCKET_API_PATH = "/api/core/v1/edge/control"

    protected getter store : PlaceOS::Core::DriverStore
    getter runtime_store : RuntimeStore
    getter runtime_manager : RuntimeManager
    @binary_manager : BinaryManager? = nil
    @desired_state : DesiredStateClient? = nil
    @reconciler : Reconciler? = nil

    private getter secret : String
    private getter edge_id : String
    private getter poll_interval : Time::Span
    private getter! uri : URI
    @realtime : RealtimeChannel? = nil

    # NOTE: injected socket controls are only for deterministic spec coverage of
    # realtime transport behavior; production flow uses the normal websocket path.
    private getter? skip_handshake : Bool
    private getter? ping : Bool
    private getter? sync_injected_socket : Bool

    private getter close_channel = Channel(Nil).new
    @connect_sync_count = Atomic(Int32).new(0)
    @injected_socket_mode : Bool = false

    def initialize(
      uri : URI = PLACE_URI,
      secret : String? = nil,
      @edge_id : String = EDGE_ID,
      @skip_handshake : Bool = false,
      @ping : Bool = true,
      @sync_injected_socket : Bool = false,
      @store : PlaceOS::Core::DriverStore = PlaceOS::Core::DriverStore.new,
      @runtime_store : RuntimeStore = RuntimeStore.new,
      @poll_interval : Time::Span = SNAPSHOT_POLL_INTERVAL,
    )
      # Validate configuration
      raise ArgumentError.new("edge_id cannot be empty") if @edge_id.empty?
      raise ArgumentError.new("poll_interval must be positive") if @poll_interval <= Time::Span.zero

      @secret = if secret && secret.presence
                  secret
                else
                  Log.info { "using PLACE_EDGE_KEY from environment" }
                  CLIENT_SECRET
                end

      raise ArgumentError.new("secret cannot be empty") if @secret.empty?

      @uri = uri.dup

      @runtime_manager = RuntimeManager.new(
        store: store,
        on_setting_callback: ->on_setting(String, String, String),
        on_redis_callback: ->on_redis(Protocol::RedisAction, String, String, String?)
      )

      @binary_manager = binary_manager = BinaryManager.new(edge_id, self.uri, @secret, @store)
      @desired_state = DesiredStateClient.new(edge_id, self.uri, @secret)
      @reconciler = Reconciler.new(
        runtime_store: @runtime_store,
        binary_manager: binary_manager,
        runtime_manager: @runtime_manager,
        on_event: ->send_runtime_event(State::RuntimeEvent)
      )
    end

    # Initialize the WebSocket API and desired-state polling loop.
    def connect(initial_socket : HTTP::WebSocket? = nil, &)
      Log.info { "connecting to #{uri}" }
      @injected_socket_mode = !initial_socket.nil?

      channel = RealtimeChannel.new(uri, secret, edge_id, ping? || false)
      @realtime = channel
      channel.connect(
        initial_socket,
        on_disconnect: ->on_disconnect(IO::Error | HTTP::WebSocket::CloseCode),
        on_connect: ->on_connect
      ) do |message|
        if request = message[1].as?(Protocol::Server::Request)
          handle_request(message[0], request)
        else
          Log.error { {message: "unexpected core request", request: message[1].to_json} }
        end
      end

      spawn { desired_state_loop } unless skip_handshake? || injected_socket_mode?

      load_persisted_snapshot unless skip_handshake? || injected_socket_mode?

      yield

      close_channel.receive?
      realtime?.try &.disconnect
    end

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
        boolean_command(sequence_id, request) { debug(request.module_id) }
      in Protocol::Message::DriverLoaded
        boolean_command(sequence_id, request) { runtime_manager.driver_loaded?(request.driver_key) }
      in Protocol::Message::DriverStatus
        send_response(sequence_id, Protocol::Message::DriverStatusResponse.new(runtime_manager.driver_status(request.driver_key)))
      in Protocol::Message::Execute
        success, output, response_code = begin
          result = runtime_manager.execute(request.module_id, request.payload, user_id: request.user_id)
          {true, result[0], result[1]}
        rescue error : PlaceOS::Driver::RemoteException
          Log.error(exception: error) { {module_id: request.module_id, message: "execute errored"} }
          {false, {message: error.message, backtrace: error.backtrace?, code: error.code}.to_json, error.code}
        end

        send_response(sequence_id, Protocol::Message::ExecuteResponse.new(success, output, response_code))
      in Protocol::Message::Ignore
        boolean_command(sequence_id, request) { ignore(request.module_id) }
      in Protocol::Message::Kill
        boolean_command(sequence_id, request) { runtime_manager.kill(request.driver_key) }
      in Protocol::Message::Load
        boolean_command(sequence_id, request) { runtime_manager.load(request.module_id, request.driver_key) }
      in Protocol::Message::LoadedModules
        send_response(sequence_id, Protocol::Message::LoadedModulesResponse.new(runtime_manager.loaded_modules))
      in Protocol::Message::ModuleLoaded
        boolean_command(sequence_id, request) { runtime_manager.module_loaded?(request.module_id) }
      in Protocol::Message::RunCount
        send_response(sequence_id, Protocol::Message::RunCountResponse.new(count: runtime_manager.run_count))
      in Protocol::Message::Start
        boolean_command(sequence_id, request) { runtime_manager.start(request.module_id, request.payload) }
      in Protocol::Message::Stop
        boolean_command(sequence_id, request) { runtime_manager.stop(request.module_id) }
      in Protocol::Message::SystemStatus
        send_response(sequence_id, Protocol::Message::SystemStatusResponse.new(runtime_manager.system_status))
      in Protocol::Message::Unload
        boolean_command(sequence_id, request) do
          runtime_manager.unload(request.module_id)
          runtime_store.delete_runtime_module(request.module_id)
          true
        end
      in Protocol::Message::Body
        Log.warn { {message: "unexpected message in handle request", type: request.type.to_s} }
      end
    rescue e
      Log.error(exception: e) { {message: "failed to handle core request", request: request.to_json} }
    end

    def drivers
      binary_manager.compiled_drivers
    end

    def driver_loaded?(driver_key : String) : Bool
      runtime_manager.driver_loaded?(driver_key)
    end

    def module_loaded?(module_id : String) : Bool
      runtime_manager.module_loaded?(module_id)
    end

    def driver_status(driver_key : String)
      runtime_manager.driver_status(driver_key)
    end

    def loaded_modules
      runtime_manager.loaded_modules
    end

    def run_count
      runtime_manager.run_count
    end

    def apply_snapshot(snapshot : State::Snapshot)
      reconciler.apply(snapshot)
    end

    def protocol_manager_by_driver?(driver_key : String)
      runtime_manager.protocol_manager_by_driver?(driver_key)
    end

    def protocol_manager_by_module?(module_id : String)
      runtime_manager.protocol_manager_by_module?(module_id)
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
          runtime_manager.debug(module_id, &callback)
        end
      end
    end

    def ignore(module_id : String)
      debug_lock.synchronize do
        callback = debug_callbacks.delete(module_id)
        runtime_manager.ignore(module_id, &callback) unless callback.nil?
      end
    end

    def forward_debug_message(module_id, message)
      spawn do
        send_event(Protocol::Message::DebugMessage.new(module_id, message))
      rescue error
        Log.error(exception: error) { {message: "forward_debug_message errored", module_id: module_id} }
      end
    end

    # Edge-originated sync
    ###########################################################################

    def on_setting(module_id : String, setting_name : String, setting_value : String)
      request = Protocol::Message::SettingsAction.new(
        module_id: module_id,
        setting_name: setting_name,
        setting_value: setting_value
      )

      Protocol.request(request, expect: Protocol::Message::Success)
    end

    def on_redis(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?)
      update = runtime_store.queue_update(action, hash_id, key_name, status_value)
      flush_update(update) if connected?
    end

    private def flush_pending_updates
      runtime_store.pending_updates.each do |update|
        flush_update(update)
      end
    end

    private def flush_pending_events
      runtime_store.pending_events.each do |pending|
        flush_event(pending)
      end
    end

    private def flush_update(update : State::PendingRedisUpdate)
      return unless connected?
      return if injected_socket_mode? && !sync_injected_socket?

      request = Protocol::Message::ProxyRedis.new(
        action: update.action,
        hash_id: update.hash_id,
        key_name: update.key_name,
        status_value: update.status_value,
      )

      response = Protocol.request(request, expect: Protocol::Message::Success)
      runtime_store.acknowledge_update(update.id) if response.try(&.success)
    end

    private def send_runtime_event(event : State::RuntimeEvent)
      pending = runtime_store.queue_event(event)
      flush_event(pending) if connected?
    end

    private def flush_event(pending : State::PendingRuntimeEvent)
      return unless connected?
      return if injected_socket_mode? && !sync_injected_socket?

      event = pending.event

      request = Protocol::Message::RuntimeEvent.new(
        kind: event.kind.to_s.underscore,
        module_id: event.module_id,
        driver_key: event.driver_key,
        message: event.message,
        snapshot_version: event.snapshot_version,
        backlog_depth: event.backlog_depth
      )

      response = Protocol.request(request, expect: Protocol::Message::Success)
      runtime_store.acknowledge_event(pending.id) if response.try(&.success)
    end

    private def send_heartbeat
      return unless connected?
      return if injected_socket_mode? && !sync_injected_socket?

      request = Protocol::Message::Heartbeat.new(
        timestamp: Time.utc,
        snapshot_version: runtime_store.last_snapshot_version,
        pending_updates: runtime_store.pending_update_count,
        pending_events: runtime_store.pending_event_count
      )

      Protocol.request(request, expect: Protocol::Message::Success)
    end

    private def on_connect
      flush_pending_updates
      flush_pending_events
      send_heartbeat
      @connect_sync_count.add(1)
      nil
    end

    private def on_disconnect(_error : IO::Error | HTTP::WebSocket::CloseCode)
      nil
    end

    private def connected?
      realtime?.try(&.closed?) == false
    end

    # Desired state reconciliation
    ###########################################################################

    private def desired_state_loop
      last_modified = runtime_store.snapshot.try(&.last_modified)

      until close_channel.closed?
        begin
          if snapshot = desired_state.fetch(last_modified)
            # Don't hold lock during reconciliation - it can take minutes
            reconciler.apply(snapshot)
            last_modified = snapshot.last_modified
          end
        rescue error
          runtime_store.set_last_error(error.message)
          send_runtime_event(State::RuntimeEvent.new(:sync_status, message: error.message, snapshot_version: runtime_store.last_snapshot_version, backlog_depth: runtime_store.pending_update_count))
        ensure
          send_heartbeat if connected?
        end

        sleep poll_interval
      end
    end

    private def load_persisted_snapshot
      if snapshot = runtime_store.snapshot
        reconciler.apply(snapshot)
      end
    rescue error
      runtime_store.set_last_error(error.message)
    end

    # Transport
    ###########################################################################

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
      channel = realtime?
      raise "cannot send response over closed transport" if channel.nil?
      channel.send_response(sequence_id, response)
    end

    protected def send_request(request : Protocol::Client::Request)
      channel = realtime?
      raise "cannot send request over closed transport" if channel.nil?
      channel.send_request(request)
    end

    protected def send_event(request : Protocol::Client::Request)
      channel = realtime?
      raise "cannot send event over closed transport" if channel.nil?
      channel.send_event(request)
    end

    private def realtime?
      @realtime
    end

    private def injected_socket_mode?
      @injected_socket_mode
    end

    private def binary_manager
      @binary_manager.not_nil!
    end

    private def desired_state
      @desired_state.not_nil!
    end

    private def reconciler
      @reconciler.not_nil!
    end
  end
end
