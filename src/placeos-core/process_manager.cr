require "placeos-driver/protocol/management"

require "./error"

module PlaceOS::Core
  module ProcessManager
    alias Request = PlaceOS::Driver::Protocol::Request

    macro included
      Log = ::Log.for(self)
    end

    abstract def load(module_id : String, driver_path : String)

    abstract def unload(module_id : String)

    abstract def start(module_id : String, payload : String)

    abstract def stop(module_id : String)

    abstract def debug(module_id : String, &on_message : String ->)

    abstract def ignore(module_id : String, &on_message : String ->)

    abstract def kill(driver_path : String)

    def ignore(module_id : String)
      ignore(module_id) { }
    end

    # Execute a driver method on a module
    #
    abstract def execute(module_id : String, payload : String)

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
    abstract def driver_status(driver_path) : DriverStatus?

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
    abstract def module_loaded?(module_id) : Bool

    # Check for the presence of a running driver on a ProcessManager
    #
    abstract def driver_loaded?(driver_path) : Bool

    # Returns the count of ...
    # - unique drivers running
    # - module processes
    #
    abstract def run_count : NamedTuple(drivers: Int32, modules: Int32)

    # Count of distinct modules loaded on a ProcessManager
    #
    abstract def loaded_modules
  end
end
