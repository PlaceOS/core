require "hound-dog"

module Engine
  class Core::ModuleManager
    # 1-4. Repos cloned, drivers compiled
    #    * Register the instance with ETCD
    #    * Once registered, run through all the modules, consistent hashing to determine what modules need to be loaded
    # 4. Load the modules  (ruby-engine-driver test runner has sample code on how this is done)
    #    * Start the driver processes as required.
    #    * Launch the modules on those processes etc
    # 5. Once all the modules are running. Mark in etcd that load is complete.
    def initialize
    end

    def load_modules
    end

    # def manager_by_module_id : EngineDriver::Protocol::Manangement
    # end

    # def manager_by_driver_path : EngineDriver::Protocol::Manangement
    # end
  end
end
