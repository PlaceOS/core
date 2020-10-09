require "placeos-driver/protocol/management"

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

    def ignore(module_id : String)
      ignore(module_id) { }
    end

    # Execute a driver method on a module
    #
    abstract def execute(module_id : String, payload : String)

    # Handler for execute requests from a module
    #
    abstract def on_exec(request : Request, response_callback : Request ->)

    def save_setting(module_id : String, setting_name : String, setting_value : YAML::Any)
      mod = PlaceOS::Model::Module.find!(module_id)
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

    # Check for the presence of a module on a ProcessManager
    #
    abstract def module_loaded?(module_id) : Bool

    # Number of unique drivers running on a ProcessManager
    #
    abstract def running_drivers

    # Number of module processes on a ProcessManager
    #
    abstract def running_modules

    # Count of distinct modules loaded on a ProcessManager
    #
    abstract def loaded_modules
  end
end
