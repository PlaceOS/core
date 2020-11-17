require "placeos-driver/protocol/management"

require "../process_manager"

require "../../placeos-edge/transport"

module PlaceOS::Core
  class ProcessManager::Edge
    include ProcessManager

    alias Transport = PlaceOS::Edge::Transport

    getter transport : Transport
    getter edge_id : String

    def initialize(@edge_id : String, socket : HTTP::WebSocket)
      @transport = Transport.new(socket) do |(sequence_id, request)|
        if request.is_a?(Protocol::Client::Request)
          handle_request(sequence_id, request)
        else
          Log.error { {message: "unexpected edge request", request: request.to_json} }
        end
      end
    end

    def handle_request(sequence_id : UInt64, request : Protocol::Client::Request)
      case request
      in Protocol::Message::FetchBinary
        response = fetch_binary(request.driver_key)
        send_response(sequence_id, response)
      in Protocol::Message::ProxyRedis
        boolean_response(sequence_id, request) do
          on_redis(
            action: request.action,
            hash_id: request.hash_id,
            key_name: request.key_name,
            status_value: request.status_value,
          )
        end
      in Protocol::Message::Register
        register(request.module)
      in Protocol::Message::SettingsAction
        boolean_response(sequence_id, request) do
          on_setting(
            id: request.module_id,
            setting_name: request.setting_name,
            setting_value: YAML.parse(request.setting_value)
          )
        end
      end
    rescue e
      Log.error(exception: e) { {
        message: "failed to handle edge request",
        request: request.to_json,
      } }
    end

    protected def register
      # 1. edge opens a websocket connection with the REST API
      # 2. REST API consistent hashes the edge id to the right core (the core which will manage the websocket session)
      # 3. core asks edge which modules/drivers it has
      # 4. edge responds with that information
      # 5. core diffs those modules/drivers, pushes drivers the edge is missing, and unloads things that are not needed
      # 6. core asks edge to load all modules it hasn't already loaded
      # 7. core treats the edge just like any other process manager
    end

    def execute(module_id : String, payload : String)
      response = Protocol.request(Protocol::Message::Load.new(module_id, driver_path), expect: Protocol::Message::ExecuteResponse)
      response.try &.output
    end

    def load(module_id : String, driver_path : String)
      !!Protocol.request(Protocol::Message::Load.new(module_id, driver_path), expect: Protocol::Message::Success)
    end

    def unload(module_id : String)
      !!Protocol.request(Protocol::Message::Unload.new(module_id), expect: Protocol::Message::Success)
    end

    def start(module_id : String, payload : String)
      !!Protocol.request(Protocol::Message::Stop.start(module_id, payload), expect: Protocol::Message::Success)
    end

    def stop(module_id : String)
      !!Protocol.request(Protocol::Message::Stop.new(module_id), expect: Protocol::Message::Success)
    end

    def kill(driver_path : String)
      !!Protocol.request(Protocol::Message::Kill.new(driver_path), expect: Protocol::Message::Success)
    end

    # Callbacks
    ###############################################################################################

    private getter debug_lock : Mutex { Mutex.new }
    private getter debug_callbacks = Hash(String, Array(Proc(String, Nil))).new { |h, k| h[k] = [] of String -> }

    def debug(module_id : String, &on_message : String ->)
      signal = debug_lock.synchronize do
        callbacks = debug_callbacks[module_id]
        callbacks << on_message
        callbacks.size == 1
      end

      send_request(Protocol::Message::Debug.new(module_id)) if signal
    end

    def ignore(module_id : String, &on_message : String ->)
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

    def on_exec(request : Request, response_callback : Request ->)
      raise "Edge modules cannot make execute requests"
    end

    # Binaries
    ###############################################################################################

    def fetch_binary(driver_key : String) : Protocol::Message::BinaryBody
      path = File.join(PlaceOS::Compiler.bin_dir, driver_key)

      binary = Edge.read_file?(path)

      Protocol::Message::BinaryBody.new(success: !binary.nil?, key: driver_key, binary: binary)
    end

    # Metadata
    ###############################################################################################

    def driver_loaded?(driver_path : String) : Bool
      !!Protocol.request(Protocol::Message::DriverLoaded.new, expect: Protocol::Message::Success)
    end

    def module_loaded?(module_id : String) : Bool
      !!Protocol.request(Protocol::Message::RunCount.new, expect: Protocol::Message::Success)
    end

    def run_count : NamedTuple(drivers: Int32, modules: Int32)
      response = Protocol.request(Protocol::Message::RunCount.new, expect: Protocol::Message::RunCountResponse)
      raise "failed to request run count" if response.nil?

      response.count
    end

    def loaded_modules
      response = Protocol.request(Protocol::Message::LoadedModules.new, expect: Protocol::Message::LoadedModulesResponse)

      raise "failed to request loaded modules " if response.nil?

      response.status
    end

    def system_status : SystemStatus
      response = Protocol.request(Protocol::Message::SystemStatus.new, expect: Protocol::Message::SystemStatusResponse)

      raise "failed to request edge system status" if response.nil?

      response.status
    end

    def driver_status(driver_path : String) : DriverStatus?
      response = Protocol.request(Protocol::Message::DriverStatus.new(driver_path), expect: Protocol::Message::DriverStatusResponse)

      response.status
    end

    protected def boolean_response(sequence_id, request)
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

    def self.read_file?(path : String) : Slice?
      File.open(path) do |file|
        memory = IO::Memory.new
        IO.copy file, memory
        memory.to_slice
      end
    rescue e
      Log.error(exception: e) { "failed to read #{path} into slice" }
      nil
    end
  end
end
