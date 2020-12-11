require "placeos-driver/protocol/management"
require "redis-cluster"

require "../process_manager"
require "../../placeos-edge/transport"
require "../../placeos-edge/protocol"

module PlaceOS::Core
  class ProcessManager::Edge
    include ProcessManager

    alias Transport = PlaceOS::Edge::Transport
    alias Protocol = PlaceOS::Edge::Protocol

    getter transport : Transport
    getter edge_id : String

    getter redis : Redis::Client { Redis::Client.boot(REDIS_URL) }

    def initialize(@edge_id : String, socket : HTTP::WebSocket, @redis : Redis? = nil)
      @transport = Transport.new do |(sequence_id, request)|
        if request.is_a?(Protocol::Client::Request)
          handle_request(sequence_id, request)
        else
          Log.error { {message: "unexpected edge request", request: request.to_json} }
        end
      end

      spawn { transport.listen(socket) }
    end

    def handle_request(sequence_id : UInt64, request : Protocol::Client::Request)
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
        send_response(sequence_id, register(modules: request.modules, drivers: request.drivers))
      when Protocol::Message::SettingsAction
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

    def execute(module_id : String, payload : String)
      response = Protocol.request(Protocol::Message::Execute.new(module_id, payload), expect: Protocol::Message::ExecuteResponse)
      response.try &.output
    end

    def load(module_id : String, driver_path : String)
      !!Protocol.request(Protocol::Message::Load.new(module_id, Edge.path_to_key(driver_path)), expect: Protocol::Message::Success)
    end

    def unload(module_id : String)
      !!Protocol.request(Protocol::Message::Unload.new(module_id), expect: Protocol::Message::Success)
    end

    def start(module_id : String, payload : String)
      !!Protocol.request(Protocol::Message::Start.new(module_id, payload), expect: Protocol::Message::Success)
    end

    def stop(module_id : String)
      !!Protocol.request(Protocol::Message::Stop.new(module_id), expect: Protocol::Message::Success)
    end

    def kill(driver_path : String)
      !!Protocol.request(Protocol::Message::Kill.new(Edge.path_to_key(driver_path)), expect: Protocol::Message::Success)
    end

    alias Module = Protocol::Message::RegisterResponse::Module

    # Calculates the modules/drivers that the edge needs to add/remove
    #
    protected def register(drivers : Set(String), modules : Set(String))
      allocated_drivers = Set(String).new
      allocated_modules = Set(Module).new
      PlaceOS::Model::Module.on_edge(edge_id).each do |mod|
        driver = mod.driver.not_nil!
        driver_key = Compiler::Helper.driver_binary_name(driver_file: driver.file_name, commit: driver.commit, id: driver.id)
        allocated_modules << {key: driver_key, module_id: mod.id.as(String)}
        allocated_drivers << driver_key
      end

      add_modules = allocated_modules.reject { |mod| modules.includes?(mod[:module_id]) }
      remove_modules = (modules - allocated_modules.map(&.[:module_id])).to_a

      Protocol::Message::RegisterResponse.new(
        success: true,
        add_drivers: (allocated_drivers - drivers).to_a,
        remove_drivers: (drivers - allocated_drivers).to_a,
        add_modules: add_modules,
        remove_modules: remove_modules,
      )
    end

    # Callbacks
    ###############################################################################################

    private getter debug_lock : Mutex { Mutex.new }
    private getter debug_callbacks = Hash(String, Array(Proc(String, Nil))).new { |h, k| h[k] = [] of String -> }

    def forward_debug_message(module_id : String, message : String)
      debug_lock.synchronize do
        debug_callbacks[module_id].each &.call(message)
      end
    end

    def debug(module_id : String, &on_message : String -> Nil)
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
      {{ raise "Edge modules cannot make execute requests" }}
    end

    private getter redis_lock = Mutex.new

    def on_redis(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?)
      redis_lock.synchronize do
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
      path = File.join(PlaceOS::Compiler.bin_dir, driver_key)

      binary = Edge.read_file?(path)

      Protocol::Message::BinaryBody.new(success: !binary.nil?, key: driver_key, binary: binary)
    end

    # Metadata
    ###############################################################################################

    def driver_loaded?(driver_path : String) : Bool
      !!Protocol.request(Protocol::Message::DriverLoaded.new(Edge.path_to_key(driver_path)), expect: Protocol::Message::Success)
    end

    def module_loaded?(module_id : String) : Bool
      !!Protocol.request(Protocol::Message::ModuleLoaded.new(module_id), expect: Protocol::Message::Success)
    end

    def run_count : NamedTuple(drivers: Int32, modules: Int32)
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

    def driver_status(driver_path : String) : DriverStatus?
      response = Protocol.request(Protocol::Message::DriverStatus.new(Edge.path_to_key(driver_path)), expect: Protocol::Message::DriverStatusResponse)

      Log.warn { {message: "failed to request driver status", driver_path: driver_path} } if response.nil?

      response.try &.status
    end

    protected def boolean_response(sequence_id, request)
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

    def self.path_to_key(driver_path : String)
      driver_path.lchop(PlaceOS::Compiler.bin_dir).lstrip('/')
    end

    def self.read_file?(path : String) : Bytes?
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
