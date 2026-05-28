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
      # `driver_path` is derived from the actual driver's file_name + commit, not
      # a hardcoded string (which goes stale as private-drivers' master moves on).
      value = REDIS_CLIENT.hgetall(driver_path)
      value["last_executed_at"].to_i64.should be > 0
    ensure
      # Without these stops the DriverResource feed (a Resource<Model::Driver> change-feed
      # listener) keeps running across later spec files. When a subsequent spec calls
      # `clear_tables`, the feed sees the `:deleted` events and removes the shared driver
      # binaries from disk, causing later tests that launch drivers to hang on `start_process`.
      if (mm = module_manager) && (m = mod)
        mm.unload_module(m) rescue nil
      end
      resource_manager.try &.stop rescue nil
    end
  end
end
