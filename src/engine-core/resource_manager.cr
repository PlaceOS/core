require "./cloning"
require "./compilation"

# Sequences the acquisition and production of resources
module ACAEngine::Core
  class ResourceManager
    @cloning : Cloning
    @compilation : Compilation

    # @@instance = new

    def initialize
      @cloning = Cloning.new
      @compilation = Compilation.new
    end

    # def self.instance
    #   @@instance
    # end
  end
end
