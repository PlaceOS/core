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

    describe "lazy modules (launch_on_execute)" do
      it "registers lazy module without spawning driver" do
        _, driver, mod = setup(role: PlaceOS::Model::Driver::Role::Service)

        module_manager = module_manager_mock
        builder = DriverResource.new(startup: true, module_manager: module_manager)
        resource_manager = ResourceManager.new(driver_builder: builder)
        resource_manager.start { }

        mod_id = mod.id.as(String)

        mod.reload!
        mod.driver = mod.driver.not_nil!.reload!

        # Set module as lazy-load
        mod.launch_on_execute = true
        mod.running = true
        mod.save!

        # Load the lazy module
        module_manager.load_module(mod)

        # Driver should NOT be spawned
        module_manager.local_processes.run_count.modules.should eq 0
        module_manager.local_processes.module_loaded?(mod_id).should be_false

        # But module should be registered as lazy
        module_manager.lazy_module?(mod_id).should be_true

        # Metadata should be populated in Redis
        metadata = Driver::RedisStorage.with_redis { |r| r.get("interface/#{mod_id}") }
        metadata.should_not be_nil
      ensure
        module_manager.try &.stop
        resource_manager.try &.stop
      end

      it "spawns driver on execute and unloads after idle" do
        # Use a short unload delay for testing
        original_delay = ModuleManager.lazy_unload_delay
        ModuleManager.lazy_unload_delay = 500.milliseconds

        _, driver, mod = setup(role: PlaceOS::Model::Driver::Role::Service)

        module_manager = module_manager_mock
        builder = DriverResource.new(startup: true, module_manager: module_manager)
        resource_manager = ResourceManager.new(driver_builder: builder)
        resource_manager.start { }

        mod_id = mod.id.as(String)

        mod.reload!
        mod.driver = mod.driver.not_nil!.reload!

        # Set module as lazy-load
        mod.launch_on_execute = true
        mod.running = true
        mod.save!

        # Reload to get fresh associations
        mod = Model::Module.find!(mod_id)
        mod.driver = driver.reload!

        # Register the lazy module
        module_manager.load_module(mod)
        module_manager.lazy_module?(mod_id).should be_true
        module_manager.local_processes.module_loaded?(mod_id).should be_false

        # Execute should spawn driver and load module
        result, code = module_manager.local_processes.execute(
          module_id: mod_id,
          payload: ModuleManager.execute_payload(:used_for_place_testing),
          user_id: nil
        )

        result.should eq %("you can delete this file")
        code.should eq 200

        # Module should now be loaded
        module_manager.local_processes.module_loaded?(mod_id).should be_true

        # Wait for idle unload
        sleep 1.second

        # Module should be unloaded and back to lazy state
        module_manager.local_processes.module_loaded?(mod_id).should be_false
        module_manager.lazy_module?(mod_id).should be_true

        # Metadata should still be in Redis
        metadata = Driver::RedisStorage.with_redis { |r| r.get("interface/#{mod_id}") }
        metadata.should_not be_nil
      ensure
        ModuleManager.lazy_unload_delay = original_delay.not_nil!
        module_manager.try &.stop
        resource_manager.try &.stop
      end

      it "does not unload while executions are active" do
        original_delay = ModuleManager.lazy_unload_delay
        ModuleManager.lazy_unload_delay = 200.milliseconds

        _, driver, mod = setup(role: PlaceOS::Model::Driver::Role::Service)

        module_manager = module_manager_mock
        builder = DriverResource.new(startup: true, module_manager: module_manager)
        resource_manager = ResourceManager.new(driver_builder: builder)
        resource_manager.start { }

        mod_id = mod.id.as(String)

        mod.reload!
        mod.driver = mod.driver.not_nil!.reload!

        mod.launch_on_execute = true
        mod.running = true
        mod.save!

        module_manager.load_module(mod)

        # Start multiple concurrent executions
        results = Channel(Tuple(String, Int32)).new(3)

        3.times do
          spawn do
            r, c = module_manager.local_processes.execute(
              module_id: mod_id,
              payload: ModuleManager.execute_payload(:used_for_place_testing),
              user_id: nil
            )
            results.send({r, c})
          end
        end

        # Collect results
        3.times do
          result, code = results.receive
          result.should eq %("you can delete this file")
          code.should eq 200
        end

        # Module should still be loaded (unload scheduled but not executed yet)
        # Give a tiny bit of time for the last execution to complete
        sleep 50.milliseconds
        module_manager.local_processes.module_loaded?(mod_id).should be_true

        # Wait for unload
        sleep 500.milliseconds
        module_manager.local_processes.module_loaded?(mod_id).should be_false
      ensure
        ModuleManager.lazy_unload_delay = original_delay.not_nil!
        module_manager.try &.stop
        resource_manager.try &.stop
      end

      it "clears metadata when lazy module is stopped" do
        _, driver, mod = setup(role: PlaceOS::Model::Driver::Role::Service)

        module_manager = module_manager_mock
        builder = DriverResource.new(startup: true, module_manager: module_manager)
        resource_manager = ResourceManager.new(driver_builder: builder)
        resource_manager.start { }

        mod_id = mod.id.as(String)

        mod.reload!
        mod.driver = mod.driver.not_nil!.reload!

        mod.launch_on_execute = true
        mod.running = true
        mod.save!

        module_manager.load_module(mod)

        # Metadata should exist
        metadata = Driver::RedisStorage.with_redis { |r| r.get("interface/#{mod_id}") }
        metadata.should_not be_nil

        # Stop the module
        module_manager.stop_module(mod)

        # Metadata should be cleared
        metadata = Driver::RedisStorage.with_redis { |r| r.get("interface/#{mod_id}") }
        metadata.should be_nil

        # Module should not be in lazy tracking
        module_manager.lazy_module?(mod_id).should be_false
      ensure
        module_manager.try &.stop
        resource_manager.try &.stop
      end
    end

    describe "startup" do
      it "registers to redis" do
        # Clear relevant tables
        Model::Driver.clear
        Model::Module.clear
        Model::Repository.clear

        # Start module manager
        module_manager = ModuleManager.new(uri: CORE_URL)
        module_manager.start
        core_uri = URI.parse(CORE_URL)

        # Check that the node is registered in etcd
        tries = 0
        loop do
          sleep 3.seconds
          break if tries > 5 || module_manager.discovery.nodes.includes?(core_uri)
          tries += 1
        end
        module_manager.discovery.nodes.should contain(core_uri)

        # Check that the node is no longer registered in etcd
        module_manager.stop
        tries = 0
        loop do
          sleep 3.seconds
          break if tries > 5 || !module_manager.discovery.nodes.includes?(core_uri)
          tries += 1
        end

        module_manager.discovery.nodes.should_not contain(core_uri)
      ensure
        module_manager.try &.stop
      end
    end
  end
end
