require "./process_manager"

module PlaceOS::Core
  class Processes::Local
    include ProcessManager

    def execute(module_id : String, payload : String | IO)
      manager = proc_manager_by_module?(module_id)

      return if manager.nil?

      request_body = payload.is_a?(IO) ? payload.gets_to_end : payload
      manager.execute(module_id, request_body)
    end

    def load(module_id, driver_path)
      if !proc_manager_by_module?(module_id)
        if (existing_driver_manager = proc_manager_by_driver?(driver_path))
          # Use the existing driver protocol manager
          set_module_proc_manager(module_id, existing_driver_manager)
        else
          # Create a new protocol manager
          manager = Driver::Protocol::Management.new(driver_path)

          # Hook up the callbacks
          manager.on_exec = ->(request : Request, response_callback : Request ->) {
            on_exec(request, response_callback)
          }

          manager.on_setting = ->(id : String, setting_name : String, setting_value : YAML::Any) {
            save_setting(id, setting_name, setting_value)
          }

          set_module_proc_manager(module_id, manager)
          set_driver_proc_manager(driver_path, manager)
        end

        Log.info { "loaded module" }
      else
        Log.info { "module already loaded" }
      end
    end

    # Stop and unload the module from node
    #
    def unload(module_id : String)
      driver_path = path_for?(module_id)
      ::Log.with_context do
        Log.context.set({
          driver_path: driver_path,
          module_id:   module_id,
        })

        stop(module_id)

        existing_manager = set_module_proc_manager(module_id, nil)

        Log.info { "unloaded module" }

        no_module_references = (existing_manager.nil? || proc_manager_lock.synchronize {
          @module_proc_managers.none? do |_, manager|
            manager == existing_manager
          end
        })

        # Delete driver indexed manager if there are no other module references.
        if driver_path && no_module_references
          remove_driver_manager(driver_path)
          Log.info { "no modules for driver after unloading module" }
        end
      end
    end

    def start(module_id : String, payload : String)
      manager = proc_manager_by_module?(module_id)

      raise ModuleError.new("No protocol manager for #{module_id}") if manager.nil?

      manager.start(module_id, payload)
    end

    def stop(module_id : String)
      proc_manager_by_module?(module_id).try do |manager|
        manager.stop(module_id)
      end
    end

    # Callbacks
    ###############################################################################################

    def debug(module_id : String, &on_message : String ->)
      manager = proc_manager_by_module?(module_id)
      raise ModuleError.new("No protocol manager for #{module_id}") if manager.nil?

      manager.debug(module_id, &on_message)
    end

    def ignore(module_id : String, &on_message : String ->)
      manager = proc_manager_by_module?(module_id)
      raise ModuleError.new("No protocol manager for #{module_id}") if manager.nil?

      manager.ignore(module_id, &on_message)
    end

    def on_exec(request : Request, response_callback : Request ->)
    end

    def save_setting(id : String, setting_name : String, setting_value : YAML::Any)
    end

    # Metadata
    ###############################################################################################

    def module_loaded?(module_id : String) : Bool
      !proc_manager_by_module?(module_id).nil?
    end

    def driver_loaded?(driver_path : String) : Bool
      !proc_manager_by_driver?(driver_path).nil?
    end

    # The number of drivers loaded on current node
    def running_drivers
      proc_manager_lock.synchronize do
        @driver_proc_managers.size
      end
    end

    # The number of module processes on current node
    def running_modules
      proc_manager_lock.synchronize do
        @module_proc_managers.size
      end
    end

    # Map reduce the querying of what modules are loaded on running drivers
    #
    def loaded_modules : Hash(String, Array(String))
      proc_manager_lock.synchronize do
        Promise.all(@driver_proc_managers.map { |driver, manager|
          Promise.defer { {driver, manager.info} }
        }).then { |driver_info|
          loaded = {} of String => Array(String)
          driver_info.each { |(driver, info)| loaded[driver] = info }
          loaded
        }.get
      end
    end

    # Protocol Managers
    ###########################################################################

    def remove_driver_manager(key)
      set_driver_proc_manager(key, nil)
    end

    # HACK: get the driver path from the module_id
    def path_for?(module_id)
      proc_manager_lock.synchronize do
        @module_proc_managers[module_id]?.try do |manager|
          @driver_proc_managers.key_for?(manager)
        end
      end
    end

    private getter proc_manager_lock = Mutex.new

    # Mapping from module_id to protocol manager
    @module_proc_managers = {} of String => Driver::Protocol::Management

    # Mapping from driver path to protocol manager
    @driver_proc_managers = {} of String => Driver::Protocol::Management

    protected def proc_manager_by_module?(module_id) : Driver::Protocol::Management?
      proc_manager_lock.synchronize do
        @module_proc_managers[module_id]?.tap do |manager|
          Log.info { "missing module manager for #{module_id}" } if manager.nil?
        end
      end
    end

    protected def proc_manager_by_driver?(driver_path) : Driver::Protocol::Management?
      proc_manager_lock.synchronize do
        @driver_proc_managers[driver_path]?.tap do |manager|
          Log.info { "missing module manager for #{driver_path}" } if manager.nil?
        end
      end
    end

    protected def set_module_proc_manager(module_id, manager : Driver::Protocol::Management?)
      proc_manager_lock.synchronize do
        if manager.nil?
          @module_proc_managers.delete(module_id)
        else
          @module_proc_managers[module_id] = manager
          manager
        end
      end
    end

    protected def set_driver_proc_manager(driver_path, manager : Driver::Protocol::Management?)
      proc_manager_lock.synchronize do
        if manager.nil?
          @driver_proc_managers.delete(driver_path)
        else
          @driver_proc_managers[driver_path] = manager
          manager
        end
      end
    end
  end
end
