require "./cloning"
require "./compilation"

# Sequences the acquisition and production of resources
module ACAEngine::Core
  class ResourceManager
    getter cloning : Cloning
    getter compilation : Compilation

    @@instance : ResourceManager? = nil

    def initialize
      @cloning = Cloning.new
      @compilation = Compilation.new
    end

    def self.instance
      (@@instance || ResourceManager.new).as(ResourceManager)
    end
  end
end
