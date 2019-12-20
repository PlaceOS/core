require "action-controller/logger"

require "./cloning"
require "./compilation"
require "./mappings"

# Sequences the acquisition and production of resources
module ACAEngine::Core
  class ResourceManager
    getter cloning : Cloning
    getter compilation : Compilation
    getter mappings : Mappings

    @@instance : ResourceManager?

    Habitat.create do
      setting logger : ActionController::Logger::TaggedLogger = ActionController::Logger::TaggedLogger.new(Logger.new(STDOUT))
      setting testing : Bool = false
    end

    def self.instance : ResourceManager
      (@@instance ||= ResourceManager.new).as(ResourceManager)
    end

    def initialize(
      cloning : Cloning? = nil,
      compilation : Compilation? = nil,
      mappings : Mappings? = nil
    )
      @cloning = cloning || Cloning.new(testing: settings.testing)
      @compilation = compilation || Compilation.new
      @mappings = mappings || Mappings.new
    end

    def start
      settings.logger.info("cloning repositories")
      cloning.start

      settings.logger.info("compiling drivers")
      compilation.start

      # Run the on-load processes
      yield

      settings.logger.info("maintaining mappings")
      mappings.start
    end
  end
end
