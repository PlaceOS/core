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
      value = case data = REDIS_CLIENT.hgetall(driver_path)
              in Hash
                data.transform_keys(&.to_s).transform_values(&.to_s)
              in Array
                hash = {} of String => String
                data.each_slice(2) do |slice|
                  next unless field = slice[0]?
                  next unless raw = slice[1]?
                  hash[field.to_s] = raw.to_s
                end
                hash
              end
      value["last_executed_at"].to_i64.should be > 0
    ensure
      module_manager.try &.stop
      resource_manager.try &.stop
    end
  end
end
