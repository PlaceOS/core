require "action-controller/logger"

require "./cloning"
require "./compilation"
require "./mappings/control_system_modules"
require "./mappings/module_names"

# Sequences the acquisition and production of resources
#
module PlaceOS::Core
  class ResourceManager
    alias TaggedLogger = ActionController::Logger::TaggedLogger

    class_property logger : TaggedLogger = TaggedLogger.new(ActionController::Base.settings.logger)
    getter cloning : Cloning
    getter compilation : Compilation
    getter control_system_modules : Mappings::ControlSystemModules
    getter module_names : Mappings::ModuleNames
    getter logger : TaggedLogger
    getter? started = false

    @@instance : ResourceManager?

    def self.instance(testing = false) : ResourceManager
      (@@instance ||= ResourceManager.new(testing: testing)).as(ResourceManager)
    end

    def initialize(
      cloning : Cloning? = nil,
      compilation : Compilation? = nil,
      control_system_modules : Mappings::ControlSystemModules? = nil,
      module_names : Mappings::ModuleNames? = nil,
      logger : ActionController::Logger::TaggedLogger? = nil,
      testing : Bool = false
    )
      @logger = logger || ResourceManager.logger
      @cloning = cloning || Cloning.new(testing: testing, logger: @logger)
      @compilation = compilation || Compilation.new(logger: @logger)
      @control_system_modules = control_system_modules || Mappings::ControlSystemModules.new(logger: @logger)
      @module_names = module_names || Mappings::ModuleNames.new(logger: @logger)
    end

    def start
      return if started?

      @started = true
      logger.info("cloning Repositories")
      cloning.start

      logger.info("compiling Drivers")
      compilation.start

      # Run the on-load processes
      yield

      logger.info("maintaining ControlSystem Module redis mappings")
      control_system_modules.start

      logger.info("synchronising Module name changes with redis mappings")
      module_names.start
    end

    def stop
      return unless started?

      @started = false
      cloning.stop
      compilation.stop
      control_system_modules.stop
      module_names.stop
    end
  end
end
