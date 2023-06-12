require "./helper"

module PlaceOS::Core
  describe ModuleManager, tags: "processes" do
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
        _, driver, mod = setup

        module_manager = module_manager_mock

        builder = DriverResource.new(startup: true, module_manager: module_manager)
        # Clone, compile, etcd
        resource_manager = ResourceManager.new(driver_builder: builder) # (cloning: cloning, compilation: compilation)
        resource_manager.start { }

        mod_id = mod.id.as(String)

        driver_path = module_manager.store.driver_binary_path(driver.file_name, driver.commit).to_s

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

        sleep 3

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
