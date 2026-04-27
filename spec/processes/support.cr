require "../helper"

module PlaceOS::Core::ProcessManager
  class_getter(store : DriverStore) { DriverStore.new }

  def self.with_driver(&)
    _, driver, mod = setup(role: PlaceOS::Model::Driver::Role::Service)
    result = DriverResource.load(driver, store, true)

    driver_key = ProcessManager.path_to_key(result.path)
    yield mod, result.path, driver_key, driver
  end

  def self.test_starting(manager, mod, driver_key)
    module_id = mod.id.as(String)
    manager.load(module_id: module_id, driver_key: driver_key)
    manager.start(module_id: module_id, payload: ModuleManager.start_payload(mod))
    manager.loaded_modules.should eq({driver_key => [module_id]})
  end
end
