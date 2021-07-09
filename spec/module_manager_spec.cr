require "./helper"

module PlaceOS::Core
  describe ModuleManager do
    describe "edge" do
    end

    describe "local" do
      it "loads modules that hash to the node" do
        _, _, _, resource_manager = create_resources

        # Start module manager
        module_manager = module_manager_mock
        module_manager.start

        # Check that the module is loaded, and the module manager can be received
        module_manager.local_processes.run_count.modules.should eq 1
        module_manager.stop
      ensure
        module_manager.try &.stop
        resource_manager.try &.stop
      end

      it "load_module" do
        _, repo, driver, mod = setup

        module_manager = module_manager_mock

        cloning = Cloning.new(testing: true)
        compilation = Compilation.new(startup: true, module_manager: module_manager)

        # Clone, compile, etcd
        resource_manager = ResourceManager.new(cloning: cloning, compilation: compilation)
        resource_manager.start { }

        mod_id = mod.id.as(String)
        driver_id = driver.id.as(String)

        driver_commit_hash = Compiler::Git.current_file_commit(driver.file_name, repo.folder_name, Compiler.repository_dir)
        driver_path = PlaceOS::Compiler::Helper.driver_binary_path(driver.file_name, driver_commit_hash, driver_id)

        mod.reload!
        mod.driver = mod.driver.not_nil!.reload!

        module_manager.load_module(mod)

        module_manager.local_processes.run_count.should eq(ProcessManager::Count.new(1, 1))

        module_manager.local_processes.protocol_manager_by_module?(mod_id).should_not be_nil
        module_manager.local_processes.protocol_manager_by_driver?(driver_path).should_not be_nil

        module_manager.local_processes.protocol_manager_by_module?(mod_id).should eq(module_manager.local_processes.protocol_manager_by_driver?(driver_path))
      ensure
        module_manager.try &.stop
        resource_manager.try &.stop
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
        module_manager.discovery.nodes.map(&.[:name]).should contain(module_manager.discovery.name)

        module_manager.discovery.unregister
        sleep 0.1

        # Check that the node is no longer registered in etcd
        module_manager.discovery.nodes.map(&.[:name]).should_not contain(module_manager.discovery.name)
      ensure
        module_manager.try &.stop
      end
    end
  end
end
