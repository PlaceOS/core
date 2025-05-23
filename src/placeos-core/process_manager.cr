require "placeos-driver/protocol/management"

require "./error"

module PlaceOS::Core
  module ProcessManager
    alias Request = PlaceOS::Driver::Protocol::Request
    alias DebugCallback = PlaceOS::Driver::Protocol::Management::DebugCallback

    record Count, drivers : Int32, modules : Int32 { include JSON::Serializable }

    macro included
      Log = ::Log.for(self)
    end

    abstract def load(module_id : String, driver_key : String)

    abstract def unload(module_id : String)

    abstract def start(module_id : String, payload : String)

    abstract def stop(module_id : String)

    def attach_debugger(module_id : String, socket : HTTP::WebSocket)
      Log.trace { {message: "binding debug session to module", module_id: module_id} }

      channel = Channel(String).new(capacity: 1)

      callback : String -> Nil = ->(message : String) do
        channel.send(message) unless channel.closed?
      end

      # Stop debugging when the socket closes
      socket.on_close do
        channel.close
        ignore(module_id, &callback)
      end

      # Attach the debug callback for the module
      debug(module_id, &callback)

      # Asyncronously send debug messages from the module
      spawn do
        while message = channel.receive?
          socket.send(message)
        end
      end
    end

    abstract def debug(module_id : String, &_on_message : DebugCallback)

    abstract def ignore(module_id : String, &_on_message : DebugCallback)

    abstract def ignore(module_id : String) : Array(DebugCallback)

    abstract def kill(driver_key : String)

    # Execute a driver method on a module
    #
    abstract def execute(module_id : String, payload : String, user_id : String?)

    # Handler for execute requests from a module
    #
    abstract def on_exec(request : Request, response_callback : Request ->)

    # Handler for settings updates
    #
    def on_setting(id : String, setting_name : String, setting_value : YAML::Any)
      mod = PlaceOS::Model::Module.find!(id)
      if setting = mod.settings_at?(:none)
      else
        setting = PlaceOS::Model::Settings.new
        setting.parent = mod
        setting.encryption_level = :none
      end

      settings_hash = setting.any
      settings_hash[YAML::Any.new(setting_name)] = setting_value
      setting.settings_string = settings_hash.to_yaml
      setting.save!
    end

    # Handler for retrieving `PlaceOS::Model::ControlSystem`s for logic modules
    #
    abstract def on_system_model(request : Request, response_callback : Request ->)

    # Metadata
    ###############################################################################################

    record(
      DriverStatus,
      running : Bool,
      module_instances : Int32,
      last_exit_code : Int32,
      launch_count : Int32,
      launch_time : Int64,
      percentage_cpu : Float64?,
      memory_total : Int64?,
      memory_usage : Int64?
    ) { include JSON::Serializable }

    # Generate a system status report
    #
    abstract def driver_status(driver_key : String) : DriverStatus?

    record(
      SystemStatus,
      hostname : String,
      cpu_count : Int64,
      # Percentage of the total CPU available
      core_cpu : Float64,
      total_cpu : Float64,
      # Memory in KB
      memory_total : Int32,
      memory_usage : Int32,
      core_memory : Int32
    ) { include JSON::Serializable }

    # Generate a system status report
    #
    abstract def system_status : SystemStatus

    # Check for the presence of a module on a ProcessManager
    #
    abstract def module_loaded?(module_id : String) : Bool

    # Check for the presence of a running driver on a ProcessManager
    #
    abstract def driver_loaded?(driver_key : String) : Bool

    # Returns the count of ...
    # - unique drivers running
    # - module processes
    #
    abstract def run_count : Count

    # Count of distinct modules loaded on a ProcessManager
    #
    abstract def loaded_modules

    # Helper for extracting the driver key
    #
    def self.path_to_key(path : String) : String
      Path[path].basename
    end
  end
end
