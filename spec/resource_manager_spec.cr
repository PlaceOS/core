require "./helper"

module ACAEngine::Core
  describe ResourceManager do
    it "clones and compiles" do
      resource_manager = ResourceManager.new
      resource_manager.cloning.processed.size.should eq 1
      resource_manager.compilation.processed.size.should eq 1
    end
  end
end
