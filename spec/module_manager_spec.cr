require "./helper"

class DiscoveryMock < HoundDog::Discovery
  def own_node?(key : String) : Bool
    true
  end
end

module ACAEngine::Core
  describe ModuleManager do
    it "load_module", focus: true do
      _, repo, driver, mod = setup

      begin
        commit_hash = ACAEngine::Drivers::Helper.repository_commit_hash(repo.folder_name.as(String))
        driver.update_fields(commit: commit_hash)
        repo.update_fields(commit_hash: commit_hash)
        sleep 0.2
      rescue e
        pp! e
      end

      # Clone, compile
      ResourceManager.new

      module_manager = ModuleManager.new("localhost", 4200, DiscoveryMock.new("core"))

      module_manager.load_module(mod)
      module_manager.running_modules.should eq 1
    end

    describe "startup" do
      it "registers to etcd" do
        Model::Driver.clear
        Model::Module.clear
        Model::Repository.clear

        # Start module manager
        module_manager = ModuleManager.new("localhost", 4200).start

        # Check that the node is registered in etcd
        module_manager.discovery.nodes.size.should eq 1

        module_manager.discovery.unregister
        sleep 0.1

        # Check that the node is registered in etcd
        module_manager.discovery.nodes.size.should eq 0
      end

      it "loads relevant modules" do
        # Prepare models, set working dir
        setup

        # Clone, compile
        ResourceManager.new

        # Start module manager
        module_manager = ModuleManager.new("localhost", 4200).start

        # Check that the module is loaded, and the module manager can be received
        module_manager.running_modules.should eq 1
      end
    end
  end
end
