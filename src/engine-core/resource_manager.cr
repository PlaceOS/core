require "./cloning"
require "./compilation"

# Sequences the acquisition and production of resources
module ACAEngine::Core
  class ResourceManager
    getter cloning : Cloning
    getter compilation : Compilation

    @@instance : ResourceManager? = nil

    def initialize
      print "Cloning repositories..."
      @cloning = Cloning.new
      puts "done"

      print "Compiling drivers..."
      @compilation = Compilation.new
      puts "done"
    end

    def self.instance
      (@@instance || ResourceManager.new).as(ResourceManager)
    end
  end
end
