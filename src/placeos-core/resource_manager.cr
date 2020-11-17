require "./cloning"
require "./compilation"
require "./mappings/control_system_modules"
require "./mappings/module_names"

# Sequences the acquisition and production of resources
#
module PlaceOS::Core
  class ResourceManager
    getter cloning : Cloning
    getter compilation : Compilation
    getter control_system_modules : Mappings::ControlSystemModules
    getter module_names : Mappings::ModuleNames
    getter settings_updates : SettingsUpdate
    getter? started = false

    private getter start_lock = Mutex.new

    @@instance : ResourceManager?

    def self.instance(testing = false) : ResourceManager
      (@@instance ||= ResourceManager.new(testing: testing)).as(ResourceManager)
    end

    def initialize(
      cloning : Cloning? = nil,
      @compilation : Compilation = Compilation.new,
      @control_system_modules : Mappings::ControlSystemModules = Mappings::ControlSystemModules.new,
      @module_names : Mappings::ModuleNames = Mappings::ModuleNames.new,
      @settings_updates : SettingsUpdate = SettingsUpdate.new,
      testing : Bool = false
    )
      @cloning = cloning || Cloning.new(testing: testing)
    end

    def start
      start_lock.synchronize {
        return if started?

        Log.info { "cloning Repositories" }
        cloning.start

        Log.info { "compiling Drivers" }
        compilation.start

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
      cloning.stop
      compilation.stop
      control_system_modules.stop
      module_names.stop
      settings_updates.stop
    end
  end
end
