# require "./cloning"
# require "./compilation"
require "./driver_manager"
require "./mappings/control_system_modules"
require "./mappings/module_names"
require "./mappings/driver_module_names"

# Sequences the acquisition and production of resources
#
module PlaceOS::Core
  class ResourceManager
    # getter cloning : Cloning
    # getter compilation : Compilation
    getter driver_builder : DriverResource
    getter control_system_modules : Mappings::ControlSystemModules
    getter module_names : Mappings::ModuleNames
    getter driver_module_names : Mappings::DriverModuleNames
    getter settings_updates : SettingsUpdate
    getter? started = false

    private getter start_lock = Mutex.new

    @@instance : ResourceManager?

    def self.instance(testing = false) : ResourceManager
      (@@instance ||= ResourceManager.new(testing: testing)).as(ResourceManager)
    end

    def initialize(
      @driver_builder : DriverResource = DriverResource.new,
      @control_system_modules : Mappings::ControlSystemModules = Mappings::ControlSystemModules.new,
      @module_names : Mappings::ModuleNames = Mappings::ModuleNames.new,
      @settings_updates : SettingsUpdate = SettingsUpdate.new,
      @driver_module_names : Mappings::DriverModuleNames = Mappings::DriverModuleNames.new,
      testing : Bool = false,
    )
    end

    def start(&)
      start_lock.synchronize {
        return if started?

        Log.info { "Starting Driver change feed listener" }
        driver_builder.start

        # Run the on-load processes
        yield

        Log.info { "maintaining ControlSystem Module redis mappings" }
        control_system_modules.start

        Log.info { "watching for Driver `module_name` changes" }
        driver_module_names.start

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
      driver_builder.stop
      control_system_modules.stop
      module_names.stop
      settings_updates.stop
    end
  end
end
