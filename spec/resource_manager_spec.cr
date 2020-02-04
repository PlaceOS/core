require "./helper"
require "engine-drivers/helper"

module ACAEngine::Core
  describe ResourceManager do
    it "loads relevant resources" do
      setup

      # Clone, compile
      cloning = Cloning.new(testing: true)
      mappings = Mappings.new(startup: false)
      resource_manager = ResourceManager.new(cloning: cloning, mappings: mappings)

      called = false
      resource_manager.start { called = true }

      called.should be_true

      # 1 if test model already present in db, 2 if not
      # Commit hash is updated, so model might be received again during startup
      {1, 2}.any?(resource_manager.cloning.processed.size).should be_true
      {1, 2}.any?(resource_manager.compilation.processed.size).should be_true

      resource_manager.mappings.processed.size.should eq 0
      resource_manager.stop
    end
  end
end
