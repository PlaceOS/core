require "./helper"
require "engine-drivers/helper"

module ACAEngine::Core
  describe ResourceManager do
    it "clones and compiles" do
      setup

      resource_manager = ResourceManager.new

      # Commit hash is updated, so model will be received again during startup
      resource_manager.cloning.processed.size.should eq 2
      resource_manager.compilation.processed.size.should eq 1
    end
  end
end
