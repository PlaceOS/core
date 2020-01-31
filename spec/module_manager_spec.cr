require "./helper"

module ACAEngine::Core
  describe ModuleManager do
    it "load_module" do
      _, repo, driver, mod = setup

      repo_folder = repo.folder_name.as(String)
      driver_file_name = driver.file_name.as(String)

      begin
        repo_commit_hash = ACAEngine::Drivers::Helper.repository_commit_hash(repo_folder)
        driver_commit_hash = ACAEngine::Drivers::Helper.file_commit_hash(driver_file_name, repo_folder)
        driver.update_fields(commit: driver_commit_hash)
        repo.update_fields(commit_hash: repo_commit_hash)
        sleep 0.2
      rescue e
        pp! e
      end

      cloning = Cloning.new(testing: true)
      # Clone, compile
      ResourceManager.new(cloning: cloning)

      mod_id = mod.id.as(String)
      driver_commit_hash = ACAEngine::Drivers::Helper.file_commit_hash(driver_file_name, repo_folder)
      driver_path = ACAEngine::Drivers::Helper.driver_binary_path(driver_file_name, driver_commit_hash)

      module_manager = ModuleManager.new("localhost", 4200, discovery: DiscoveryMock.new("core"))

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
        create_resources

        # Start module manager
        module_manager = ModuleManager.new("localhost", 4200).start

        # Check that the module is loaded, and the module manager can be received
        module_manager.running_modules.should eq 1
      end
    end
  end
end
