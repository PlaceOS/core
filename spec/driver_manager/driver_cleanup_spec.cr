require "../helper"

module PlaceOS::Core
  describe DriverCleanup do
    it "should capture and retrieve stale drivers" do
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

      tracker = DriverCleanup::StaleProcessTracker.new(DriverStore::BINARY_PATH, REDIS_CLIENT)
      stale_list = tracker.update_and_find_stale(ENV["STALE_THRESHOLD_DAYS"]?.try &.to_i || 30)
      stale_list.size.should eq(0)
      driver_file = Path[DriverStore::BINARY_PATH, "drivers_place_private_helper_cce023a_#{Core::ARCH}"].to_s
      value = REDIS_CLIENT.hgetall(driver_file)
      value["last_executed_at"].to_i64.should be > 0
    end
  end
end
