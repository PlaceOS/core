require "./helper"

class DiscoveryMock < HoundDog::Discovery
  def own_node?(key : String) : Bool
    true
  end
end

module ACAEngine::Core
  describe ModuleManager do
    it "load_module" do
      _, repo, driver, mod = setup

      repo_folder = repo.folder_name.as(String)

      begin
        commit_hash = ACAEngine::Drivers::Helper.repository_commit_hash(repo_folder)
        driver.update_fields(commit: commit_hash)
        repo.update_fields(commit_hash: commit_hash)
        sleep 0.2
      rescue e
        pp! e
      end

      # Clone, compile
      ResourceManager.new

      mod_id = mod.id.as(String)
      driver_file_name = driver.file_name.as(String)
      driver_commit = ACAEngine::Drivers::Helper.repository_commit_hash(repo_folder)
      driver_path = ACAEngine::Drivers::Helper.driver_binary_path(driver_file_name, driver_commit)

      module_manager = ModuleManager.new("localhost", 4200, DiscoveryMock.new("core"))

      module_manager.load_module(mod)
      module_manager.running_modules.should eq 1
      module_manager.running_drivers.should eq 1

      module_manager.manager_by_module_id(mod_id).should_not be_nil
      module_manager.manager_by_driver_path(driver_path).should_not be_nil

      module_manager.manager_by_module_id(mod_id).should eq(module_manager.manager_by_driver_path(driver_path))
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
