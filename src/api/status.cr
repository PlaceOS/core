require "hardware"

require "../placeos-core/module_manager"
require "../placeos-core/resource_manager"
require "../placeos-core/edge_error"
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

    # Edge Error Monitoring Endpoints
    ###############################################################################################

    # Get errors for a specific edge
    @[AC::Route::GET("/edge/:edge_id/errors")]
    def edge_errors(
      edge_id : String,
      @[AC::Param::Info(description: "Number of recent errors to return")]
      limit : Int32 = 50,
      @[AC::Param::Info(description: "Error type filter")]
      type : String? = nil,
    ) : Array(Core::EdgeError)
      errors = module_manager.edge_errors(edge_id)[edge_id]? || [] of Core::EdgeError

      # Filter by type if specified
      if type
        error_type = Core::ErrorType.parse?(type.camelcase)
        errors = errors.select(&.error_type.==(error_type)) if error_type
      end

      errors.last(limit)
    end

    # Get module status for a specific edge
    @[AC::Route::GET("/edge/:edge_id/modules/status")]
    def edge_module_status(edge_id : String) : Core::EdgeModuleStatus
      module_manager.edge_module_status[edge_id]? || Core::EdgeModuleStatus.new(edge_id)
    end

    # Get health status for all edges
    @[AC::Route::GET("/edges/health")]
    def edges_health : Hash(String, Core::EdgeHealth)
      module_manager.edge_health_status
    end

    # Get connection status for all edges
    @[AC::Route::GET("/edges/connections")]
    def edge_connections : Hash(String, Core::ConnectionMetrics)
      module_manager.edge_connection_metrics
    end

    # Get errors from all edges
    @[AC::Route::GET("/edges/errors")]
    def all_edge_errors(
      @[AC::Param::Info(description: "Number of recent errors to return per edge")]
      limit : Int32 = 50,
      @[AC::Param::Info(description: "Error type filter")]
      type : String? = nil,
    ) : Hash(String, Array(Core::EdgeError))
      all_errors = module_manager.edge_errors

      # Filter by type if specified
      if type
        error_type = Core::ErrorType.parse?(type.camelcase)
        if error_type
          all_errors = all_errors.transform_values do |errors|
            errors.select(&.error_type.==(error_type))
          end
        end
      end

      # Apply limit to each edge
      all_errors.transform_values(&.last(limit))
    end

    # Get module failures from all edges
    @[AC::Route::GET("/edges/modules/failures")]
    def edge_module_failures : Hash(String, Array(Core::ModuleInitError))
      module_manager.edge_module_status.transform_values(&.initialization_errors)
    end

    # Get overall edge statistics
    @[AC::Route::GET("/edges/statistics")]
    def edge_statistics : EdgeStatistics
      health_status = module_manager.edge_health_status

      total_edges = health_status.size
      connected_edges = health_status.count { |_, health| health.connected }
      total_errors_24h = health_status.sum { |_, health| health.error_count_24h }
      total_modules = health_status.sum { |_, health| health.module_count }
      failed_modules = health_status.sum { |_, health| health.failed_modules.size }

      EdgeStatistics.new(
        total_edges: total_edges,
        connected_edges: connected_edges,
        disconnected_edges: total_edges - connected_edges,
        total_errors_24h: total_errors_24h,
        total_modules: total_modules,
        failed_modules: failed_modules,
        average_uptime: health_status.values.map(&.connection_uptime).sum / Math.max(1, total_edges)
      )
    end

    record EdgeStatistics,
      total_edges : Int32,
      connected_edges : Int32,
      disconnected_edges : Int32,
      total_errors_24h : Int32,
      total_modules : Int32,
      failed_modules : Int32,
      average_uptime : Time::Span do
      include JSON::Serializable

      @[JSON::Field(converter: PlaceOS::Core::TimeSpanConverter)]
      getter average_uptime : Time::Span
    end
  end
end
