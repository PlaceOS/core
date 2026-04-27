module PlaceOS::Core
  module Services
    extend self

    @@module_manager : ModuleManager?
    @@resource_manager : ResourceManager?
    @@module_manager_lock = Mutex.new
    @@resource_manager_lock = Mutex.new

    def module_manager : ModuleManager
      @@module_manager_lock.synchronize do
        @@module_manager ||= ModuleManager.instance
      end
    end

    def resource_manager : ResourceManager
      @@resource_manager_lock.synchronize do
        @@resource_manager ||= ResourceManager.instance
      end
    end

    def module_manager=(manager : ModuleManager?)
      @@module_manager_lock.synchronize do
        @@module_manager = manager
      end
    end

    def resource_manager=(manager : ResourceManager?)
      @@resource_manager_lock.synchronize do
        @@resource_manager = manager
      end
    end

    def current_module_manager? : ModuleManager?
      @@module_manager_lock.synchronize { @@module_manager }
    end

    def current_resource_manager? : ResourceManager?
      @@resource_manager_lock.synchronize { @@resource_manager }
    end

    def reset
      @@module_manager_lock.synchronize do
        @@module_manager = nil
      end
      @@resource_manager_lock.synchronize do
        @@resource_manager = nil
      end
    end
  end
end
