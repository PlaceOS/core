require "hardware"
require "auto_initialize"
require "placeos-compiler/helper"

require "../placeos-core/module_manager"
require "../placeos-core/resource_manager"
require "./application"

module PlaceOS::Core::Api
  class Status < Application
    base "/api/core/v1/status/"

    getter module_manager : ModuleManager { ModuleManager.instance }
    getter resource_manager : ResourceManager { ResourceManager.instance }

    struct RunCount
      include JSON::Serializable
      include AutoInitialize

      getter local : PlaceOS::Core::ProcessManager::Count
      getter edge : Hash(String, PlaceOS::Core::ProcessManager::Count)
    end

    struct Statistics
      include JSON::Serializable
      include AutoInitialize

      getter available_repositories : Array(String)
      getter unavailable_repositories : Array(PlaceOS::Resource::Error)
      getter compiled_drivers : Array(String)
      getter unavailable_drivers : Array(PlaceOS::Resource::Error)

      getter run_count : RunCount
    end

    # General statistics related to the process
    @[AC::Route::GET("/")]
    def statistics : Statistics
      Statistics.new(
        available_repositories: PlaceOS::Compiler::Helper.repositories,
        unavailable_repositories: resource_manager.cloning.errors,
        compiled_drivers: PlaceOS::Compiler::Helper.compiled_drivers,
        unavailable_drivers: resource_manager.compilation.errors,
        run_count: RunCount.new(
          local: module_manager.local_processes.run_count,
          edge: module_manager.edge_processes.run_count,
        ),
      )
    end

    struct DriverStatus
      include JSON::Serializable
      include AutoInitialize

      getter local : PlaceOS::Core::ProcessManager::DriverStatus?
      getter edge : Hash(String, PlaceOS::Core::ProcessManager::DriverStatus?)
    end

    # details related to a process (+ anything else we can think of)
    @[AC::Route::GET("/driver")]
    def driver(
      @[AC::Param::Info(name: "path", description: "the path of the compiled driver", example: "/path/to/compiled_driver")]
      driver_path : String
    ) : DriverStatus
      DriverStatus.new(
        local: module_manager.local_processes.driver_status(driver_path),
        edge: module_manager.edge_processes.driver_status(driver_path),
      )
    end

    struct MachineLoad
      include JSON::Serializable
      include AutoInitialize

      getter local : PlaceOS::Core::ProcessManager::SystemStatus
      getter edge : Hash(String, PlaceOS::Core::ProcessManager::SystemStatus)
    end

    # details about the overall machine load
    @[AC::Route::GET("/load")]
    def load : MachineLoad
      MachineLoad.new(
        local: module_manager.local_processes.system_status,
        edge: module_manager.edge_processes.system_status,
      )
    end

    struct LoadedModules
      include JSON::Serializable
      include AutoInitialize

      getter local : Hash(String, Array(String))
      getter edge : Hash(String, Hash(String, Array(String)))
    end

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
