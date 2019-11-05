require "./helper"
require "engine-drivers/helper"

module ACAEngine::Core
  describe ResourceManager do
    it "clones and compiles" do
      setup

      # Clone, compile
      cloning = Cloning.new(testing: true)
      resource_manager = ResourceManager.new(cloning: cloning)

      resource_manager.start { }

      # Commit hash is updated, so model will be received again during startup
      resource_manager.cloning.processed.size.should eq 2
      resource_manager.compilation.processed.size.should eq 1
      resource_manager.mappings.processed.size.should eq 0
    end
  end
end
