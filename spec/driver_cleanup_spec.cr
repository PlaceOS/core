require "./helper"

module PlaceOS::Core
  describe DriverCleanup do
    it "get running drivers information in expected format" do
      _, driver, mod = setup
      module_manager = module_manager_mock

      builder = DriverResource.new(startup: true, module_manager: module_manager)
      resource_manager = ResourceManager.new(driver_builder: builder)
      resource_manager.start { }

      mod_id = mod.id.as(String)

      driver_path = module_manager.store.driver_binary_path(driver.file_name, driver.commit).to_s

      mod.reload!
      mod.driver = mod.driver.not_nil!.reload!

      module_manager.load_module(mod)

      module_manager.local_processes.run_count.should eq(ProcessManager::Count.new(1, 1))

      expected = ["drivers_place_private_helper_cce023_#{DriverCleanup.arch}"]
      running = DriverCleanup.running_drivers
      running.should eq(expected)
      local = Dir.new(DriverStore::BINARY_PATH).children
      running.should eq(expected)
    end
  end
end
