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

      # Clone, compile, etcd
      cloning = Cloning.new(testing: true, logger: LOGGER)
      resource_manager = ResourceManager.new(cloning: cloning, logger: LOGGER)
      resource_manager.start { }

      mod_id = mod.id.as(String)
      driver_commit_hash = ACAEngine::Drivers::Helper.file_commit_hash(driver_file_name, repo_folder)
      driver_path = ACAEngine::Drivers::Helper.driver_binary_path(driver_file_name, driver_commit_hash)

      uri = "http://localhost:4200"
      module_manager = ModuleManager.new(uri, discovery: DiscoveryMock.new("core", uri: uri), logger: LOGGER)

      module_manager.load_module(mod)
      module_manager.running_modules.should eq 1
      module_manager.running_drivers.should eq 1

      module_manager.manager_by_module_id(mod_id).should_not be_nil
      module_manager.manager_by_driver_path(driver_path).should_not be_nil

      module_manager.manager_by_module_id(mod_id).should eq(module_manager.manager_by_driver_path(driver_path))

      module_manager.stop
      resource_manager.stop
    end

    describe "startup" do
      it "registers to etcd" do
        Model::Driver.clear
        Model::Module.clear
        Model::Repository.clear

        # Start module manager
        module_manager = ModuleManager.new("http://localhost:4200", logger: LOGGER).start

        # Check that the node is registered in etcd
        module_manager.discovery.nodes.size.should eq 1

        module_manager.discovery.unregister
        sleep 0.1

        # Check that the node is registered in etcd
        module_manager.discovery.nodes.size.should eq 0
        module_manager.stop
      end

      it "loads modules that hash to the node" do
        create_resources

        uri = "http://localhost:4200"
        discovery_mock = DiscoveryMock.new("core", uri: uri)
        clustering_mock = MockClustering.new(
          uri: uri,
          discovery: discovery_mock,
          logger: LOGGER
        )

        module_manager = ModuleManager.new(
          uri: uri,
          clustering: clustering_mock,
          discovery: discovery_mock,
          logger: LOGGER,
        )

        # Start module manager
        module_manager.start

        # Check that the module is loaded, and the module manager can be received
        module_manager.running_modules.should eq 1
        module_manager.stop
      end
    end
  end
end
