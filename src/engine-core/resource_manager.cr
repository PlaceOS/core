require "action-controller/logger"

require "./cloning"
require "./compilation"
require "./mappings"

# Sequences the acquisition and production of resources
module ACAEngine::Core
  class ResourceManager
    getter logger : ActionController::Logger::TaggedLogger

    getter cloning : Cloning
    getter compilation : Compilation
    getter mappings : Mappings

    @@instance : ResourceManager?

    def self.instance(testing = false) : ResourceManager
      (@@instance ||= ResourceManager.new(testing: testing)).as(ResourceManager)
    end

    def initialize(
      cloning : Cloning? = nil,
      compilation : Compilation? = nil,
      mappings : Mappings? = nil,
      @logger : ActionController::Logger::TaggedLogger = ActionController::Logger::TaggedLogger.new(ActionController::Base.settings.logger),
      testing : Bool = false
    )
      @cloning = cloning || Cloning.new(testing: testing)
      @compilation = compilation || Compilation.new
      @mappings = mappings || Mappings.new
    end

    def start
      logger.info("cloning repositories")
      @cloning.start

      logger.info("compiling drivers")
      @compilation.start

      # Run the on-load processes
      yield

      logger.info("maintaining mappings")
      @mappings.start
    end
  end
end
