require "http"
require "rwlock"

require "./protocol"
require "./transport"

require "../placeos-core/process_manager/edge"
require "../placeos-core/edge_error"

module PlaceOS::Edge
  class Server
    Log = ::Log.for(self)

    private getter edges = {} of String => Core::ProcessManager::Edge
    private getter edges_lock = RWLock.new

    # Macro generated calls for each `Core::ProcessManager::Edge`
    macro method_missing(call)
      # {{ call.name }} per edge
      edges_lock.read do
        edges.transform_values &.{{call.name.id}}({{call.args.join(", ").id}})
      end
    end

    # Maintains an Edge API, cleaning up after the socket closes
    #
    def manage_edge(edge_id : String, socket : HTTP::WebSocket)
      Log.info { {edge_id: edge_id, message: "managing edge"} }
      socket.on_close do
        edges_lock.write do
          if manager = edges[edge_id]?
            manager.track_connection_event(PlaceOS::Core::ConnectionEventType::Disconnected)
            edges.delete(edge_id)
          end
        end
      end

      manager = PlaceOS::Core::ProcessManager::Edge.new(edge_id, socket)

      edges_lock.write do
        edges[edge_id] = manager
      end
    end

    # Look up `ProcessManager::Edge` for an edge_id
    #
    def for?(edge_id : String)
      if edge = edges_lock.read { edges[edge_id]? }
        edge
      else
        Log.error { "no manager found for edge #{edge_id}" }
        nil
      end
    end

    # :ditto:
    def for?(edge_id : String, &block : PlaceOS::Core::ProcessManager::Edge ->)
      manager = for?(edge_id)
      yield manager unless manager.nil?
    end

    # Health Monitoring and Error Aggregation
    ###############################################################################################

    # Get health status for all edges
    def edge_health_status : Hash(String, PlaceOS::Core::EdgeHealth)
      edges_lock.read do
        edges.transform_values(&.get_edge_health)
      end
    end

    # Collect errors from all edges
    def collect_edge_errors : Hash(String, Array(PlaceOS::Core::EdgeError))
      edges_lock.read do
        edges.transform_values(&.get_recent_errors)
      end
    end

    # Get connection metrics for all edges
    def edge_connection_metrics : Hash(String, PlaceOS::Core::ConnectionMetrics)
      edges_lock.read do
        edges.transform_values do |manager|
          health = manager.get_edge_health
          PlaceOS::Core::ConnectionMetrics.new(
            edge_id: manager.edge_id,
            total_connections: 1, # Simplified - would need more tracking
            failed_connections: health.connected ? 0 : 1,
            average_uptime: health.connection_uptime,
            last_connection_attempt: health.last_seen,
            last_successful_connection: health.connected ? health.last_seen : Time.utc - 1.day
          )
        end
      end
    end

    # Get module status for all edges
    def edge_module_status : Hash(String, PlaceOS::Core::EdgeModuleStatus)
      edges_lock.read do
        edges.transform_values(&.get_edge_module_status)
      end
    end

    # Get errors for a specific edge
    def edge_errors(edge_id : String, limit : Int32 = 50) : Array(PlaceOS::Core::EdgeError)
      for?(edge_id) { |manager| return manager.get_recent_errors(limit) }
      [] of PlaceOS::Core::EdgeError
    end

    # Get module initialization failures for a specific edge
    def edge_module_failures(edge_id : String) : Hash(String, Array(PlaceOS::Core::ModuleInitError))
      for?(edge_id) { |manager| return manager.get_module_init_failures }
      {} of String => Array(PlaceOS::Core::ModuleInitError)
    end

    # Get connection status for all edges
    def edge_connection_status : Hash(String, Bool)
      edges_lock.read do
        edges.transform_values(&.get_edge_health.connected)
      end
    end

    # Cleanup old errors across all edges
    def cleanup_old_errors(older_than : Time::Span = 24.hours)
      edges_lock.read do
        edges.each_value(&.cleanup_old_errors(older_than))
      end
    end
  end
end
