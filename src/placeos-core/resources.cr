require "./resources/drivers"
require "./resources/settings_updates"
require "./mappings/control_system_modules"
require "./mappings/module_names"

module PlaceOS::Core::Resources
  # Sequences the acquisition and production of resources
  #
  class Manager
    getter drivers : Drivers
    getter control_system_modules : Mappings::ControlSystemModules
    getter module_names : Mappings::ModuleNames
    getter settings_updates : Resources::SettingsUpdate
    getter? started = false

    private getter start_lock = Mutex.new

    @@instance : self?

    def self.instance(testing = false) : Resources::Manager
      (@@instance ||= Resources::Manager.new(testing: testing)).as(Resources::Manager)
    end

    def initialize(
      @drivers : Drivers = Drivers.new,
      @control_system_modules : Mappings::ControlSystemModules = Mappings::ControlSystemModules.new,
      @module_names : Mappings::ModuleNames = Mappings::ModuleNames.new,
      @settings_updates : SettingsUpdate = SettingsUpdate.new,
      testing : Bool = false
    )
    end

    def start
      start_lock.synchronize {
        return if started?

        Log.info { "fetching Drivers" }
        drivers.start

        # Run the on-load processes
        yield

        Log.info { "maintaining ControlSystem Module redis mappings" }
        control_system_modules.start

        Log.info { "synchronising Module name changes with redis mappings" }
        module_names.start

        Log.info { "listening for Module Settings update" }
        settings_updates.start

        @started = true
      }
    end

    def stop
      return unless started?

      @started = false
      drivers.stop
      control_system_modules.stop
      module_names.stop
      settings_updates.stop
    end
  end
end
