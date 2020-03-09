require "action-controller/logger"

require "./cloning"
require "./compilation"
require "./mappings"

# Sequences the acquisition and production of resources
#
module PlaceOS::Core
  class ResourceManager
    alias TaggedLogger = ActionController::Logger::TaggedLogger

    class_property logger : TaggedLogger = TaggedLogger.new(ActionController::Base.settings.logger)
    getter cloning : Cloning
    getter compilation : Compilation
    getter mappings : Mappings
    getter logger : TaggedLogger
    getter? started = false

    @@instance : ResourceManager?

    def self.instance(testing = false) : ResourceManager
      (@@instance ||= ResourceManager.new(testing: testing)).as(ResourceManager)
    end

    def initialize(
      cloning : Cloning? = nil,
      compilation : Compilation? = nil,
      mappings : Mappings? = nil,
      logger : ActionController::Logger::TaggedLogger? = nil,
      testing : Bool = false
    )
      @logger = logger || ResourceManager.logger
      @cloning = cloning || Cloning.new(testing: testing, logger: @logger)
      @compilation = compilation || Compilation.new(logger: @logger)
      @mappings = mappings || Mappings.new(logger: @logger)
    end

    def start
      return if started?

      @started = true
      logger.info("cloning repositories")
      cloning.start

      logger.info("compiling drivers")
      compilation.start

      # Run the on-load processes
      yield

      logger.info("maintaining mappings")
      mappings.start
    end

    def stop
      return unless started?

      @started = false
      cloning.stop
      compilation.stop
      mappings.stop
    end
  end
end
