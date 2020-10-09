require "./helper"

module PlaceOS::Core
  describe ModuleManager do
    describe "edge" do
    end

    describe "local" do
      it "loads modules that hash to the node" do
        create_resources

        discovery_mock = DiscoveryMock.new("core", uri: CORE_URL)
        clustering_mock = MockClustering.new(
          uri: CORE_URL,
          discovery: discovery_mock,
        )

        module_manager = ModuleManager.new(
          uri: CORE_URL,
          clustering: clustering_mock,
          discovery: discovery_mock,
        )

        # Start module manager
        module_manager.start

        # Check that the module is loaded, and the module manager can be received
        module_manager.local_processes.running_modules.should eq 1
        module_manager.stop
      end

      it "load_module" do
        _, repo, driver, mod = setup

        module_manager = ModuleManager.new(CORE_URL, discovery: DiscoveryMock.new("core", uri: CORE_URL))

        cloning = Cloning.new(testing: true)
        compilation = Compilation.new(startup: true, module_manager: module_manager)

        # Clone, compile, etcd
        resource_manager = ResourceManager.new(cloning: cloning, compilation: compilation)
        resource_manager.start { }

        begin
          repo_commit_hash = PlaceOS::Compiler::Helper.repository_commit_hash(repo.folder_name)
          driver_commit_hash = PlaceOS::Compiler::Helper.file_commit_hash(driver.file_name, repo.folder_name)
          driver.update_fields(commit: driver_commit_hash)
          repo.update_fields(commit_hash: repo_commit_hash)
          sleep 0.2
        rescue e
          pp! e
          raise e
        end

        mod_id = mod.id.as(String)
        driver_id = driver.id.as(String)

        driver_commit_hash = PlaceOS::Compiler::Helper.file_commit_hash(driver.file_name, repo.folder_name)
        driver_path = PlaceOS::Compiler::Helper.driver_binary_path(driver.file_name, driver_commit_hash, driver_id)

        module_manager.load_module(mod)

        module_manager.local_processes.running_modules.should eq 1
        module_manager.local_processes.running_drivers.should eq 1

        module_manager.local_processes.proc_manager_by_module?(mod_id).should_not be_nil
        module_manager.local_processes.proc_manager_by_driver?(driver_path).should_not be_nil

        module_manager.local_processes.proc_manager_by_module?(mod_id).should eq(module_manager.local_processes.proc_manager_by_driver?(driver_path))

        module_manager.stop
        resource_manager.stop
      end
    end

    describe "startup" do
      it "registers to etcd" do
        # Remove metadata in etcd
        namespace = HoundDog.settings.service_namespace
        HoundDog.etcd_client.kv.delete_prefix(namespace)

        # Clear relevant tables
        Model::Driver.clear
        Model::Module.clear
        Model::Repository.clear

        # Start module manager
        module_manager = ModuleManager.new(uri: CORE_URL)
        module_manager.start

        # Check that the node is registered in etcd
        module_manager.discovery.nodes.size.should eq 1

        module_manager.discovery.unregister
        sleep 0.1

        # Check that the node is registered in etcd
        module_manager.discovery.nodes.size.should eq 0
        module_manager.stop
      end
    end
  end
end
