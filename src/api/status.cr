require "hardware"

require "../placeos-core/module_manager"
require "../placeos-core/resource_manager"
require "./application"

module PlaceOS::Core::Api
  class Status < Application
    base "/api/core/v1/status/"

    getter module_manager : ModuleManager { ModuleManager.instance }
    getter resource_manager : ResourceManager { ResourceManager.instance }

    record(RunCount, local : PlaceOS::Core::ProcessManager::Count,
      edge : Hash(String, PlaceOS::Core::ProcessManager::Count)) { include JSON::Serializable }

    record(Statistics, available_repositories : Array(String),
      unavailable_repositories : Array(PlaceOS::Resource::Error),
      compiled_drivers : Array(String),
      unavailable_drivers : Array(PlaceOS::Resource::Error),
      run_count : RunCount) { include JSON::Serializable }

    # General statistics related to the process
    @[AC::Route::GET("/")]
    def statistics : Statistics
      Statistics.new(
        available_repositories: [] of String,                     # PlaceOS::Compiler::Helper.repositories,
        unavailable_repositories: [] of PlaceOS::Resource::Error, # resource_manager.cloning.errors,
        compiled_drivers: module_manager.store.compiled_drivers,  # PlaceOS::Compiler::Helper.compiled_drivers,
        unavailable_drivers: resource_manager.driver_builder.errors,
        run_count: RunCount.new(
          local: module_manager.local_processes.run_count,
          edge: module_manager.edge_processes.run_count,
        ),
      )
    end

    record(DriverStatus, local : PlaceOS::Core::ProcessManager::DriverStatus?,
      edge : Hash(String, PlaceOS::Core::ProcessManager::DriverStatus?)) { include JSON::Serializable }

    # details related to a process (+ anything else we can think of)
    @[AC::Route::GET("/driver")]
    def driver(
      @[AC::Param::Info(name: "path", description: "the path of the compiled driver", example: "/path/to/compiled_driver")]
      driver_path : String,
    ) : DriverStatus
      DriverStatus.new(
        local: module_manager.local_processes.driver_status(driver_path),
        edge: module_manager.edge_processes.driver_status(driver_path),
      )
    end

    record(MachineLoad, local : PlaceOS::Core::ProcessManager::SystemStatus,
      edge : Hash(String, PlaceOS::Core::ProcessManager::SystemStatus)) { include JSON::Serializable }

    # details about the overall machine load
    @[AC::Route::GET("/load")]
    def load : MachineLoad
      MachineLoad.new(
        local: module_manager.local_processes.system_status,
        edge: module_manager.edge_processes.system_status,
      )
    end

    record(LoadedModules, local : Hash(String, Array(String)),
      edge : Hash(String, Hash(String, Array(String)))) { include JSON::Serializable }

    # Returns the lists of modules drivers have loaded for this core, and managed edges
    @[AC::Route::GET("/loaded")]
    def loaded : LoadedModules
      LoadedModules.new(
        local: module_manager.local_processes.loaded_modules,
        edge: module_manager.edge_processes.loaded_modules,
      )
    end
  end
end
