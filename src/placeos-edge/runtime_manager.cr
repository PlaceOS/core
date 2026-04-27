require "placeos-driver/protocol/management"

require "../placeos-core/process_manager/common"

module PlaceOS::Edge
  class RuntimeManager
    include PlaceOS::Core::ProcessManager::Common

    alias ModuleError = ::PlaceOS::Core::ModuleError

    protected getter store : PlaceOS::Core::DriverStore
    private getter on_setting_callback : (String, String, String ->)?
    private getter on_redis_callback : (Protocol::RedisAction, String, String, String? ->)?

    def initialize(
      @store : PlaceOS::Core::DriverStore = PlaceOS::Core::DriverStore.new,
      @on_setting_callback : (String, String, String ->)? = nil,
      @on_redis_callback : (Protocol::RedisAction, String, String, String? ->)? = nil,
    )
    end

    def execute(module_id : String, payload : String | IO, user_id : String?, mod : Model::Module? = nil)
      manager = protocol_manager_by_module?(module_id)
      raise ModuleError.new("No protocol manager for #{module_id}") if manager.nil?

      request_body = payload.is_a?(IO) ? payload.gets_to_end : payload
      manager.execute(
        module_id,
        request_body,
        user_id: user_id,
      )
    rescue error : PlaceOS::Driver::RemoteException
      raise error
    rescue exception
      raise module_error(module_id, exception)
    end

    def load(module_id : String, driver_key : String)
      driver_key = PlaceOS::Core::ProcessManager.path_to_key(driver_key)

      return true if protocol_manager_by_module?(module_id)

      if existing_driver_manager = protocol_manager_by_driver?(driver_key)
        set_module_protocol_manager(module_id, existing_driver_manager)
        return true
      end

      manager = Driver::Protocol::Management.new(store.path(driver_key).to_s, on_edge: true)

      manager.on_setting = ->(id : String, setting_name : String, setting_value : YAML::Any) {
        on_setting_callback.try &.call(id, setting_name, setting_value.to_yaml)
      }

      manager.on_redis = ->(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?) {
        on_redis_callback.try &.call(action, hash_id, key_name, status_value)
      }

      set_module_protocol_manager(module_id, manager)
      set_driver_protocol_manager(driver_key, manager)
      true
    rescue exception
      raise module_error(module_id, exception)
    end

    def modules
      protocol_manager_lock.synchronize do
        @module_protocol_managers.keys.to_set
      end
    end

    def protocol_manager_by_driver?(driver_key : String)
      super(driver_key)
    end

    def protocol_manager_by_module?(module_id : String)
      super(module_id)
    end
  end
end
