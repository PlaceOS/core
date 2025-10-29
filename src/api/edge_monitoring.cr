require "json"
require "http/web_socket"

require "../placeos-core/module_manager"
require "../placeos-core/edge_error"
require "./application"

module PlaceOS::Core::Api
  class EdgeMonitoring < Application
    base "/api/core/v1/monitoring/"

    getter module_manager : ModuleManager { ModuleManager.instance }

    # WebSocket endpoint for real-time error monitoring of a specific edge
    @[AC::Route::WebSocket("/edge/:edge_id/errors/stream")]
    def edge_error_stream(
      socket,
      @[AC::Param::Info(description: "the edge ID to monitor", example: "edge-1234")]
      edge_id : String,
    ) : Nil
      Log.info { {message: "edge error stream connected", edge_id: edge_id} }

      # Send initial errors
      edge_errors_hash = module_manager.edge_errors(edge_id)
      initial_errors = edge_errors_hash[edge_id]? || [] of PlaceOS::Core::EdgeError
      recent_errors = initial_errors.size > 10 ? initial_errors[-10..-1] : initial_errors

      socket.send(%({
        "type": "initial_errors",
        "edge_id": "#{edge_id}",
        "errors": #{recent_errors.to_json}
      }))

      # Keep connection alive and send periodic updates
      spawn do
        loop do
          sleep 5.seconds
          break if socket.closed?

          begin
            # Send current health status
            health = module_manager.edge_health_status[edge_id]?
            if health
              socket.send(%({
                "type": "health_update",
                "edge_id": "#{edge_id}",
                "health": #{health.to_json}
              }))
            end

            # Send recent errors (last 5 seconds worth)
            edge_errors_hash = module_manager.edge_errors(edge_id)
            recent_errors = edge_errors_hash[edge_id]? || [] of PlaceOS::Core::EdgeError
            new_errors = recent_errors.select { |error| error.timestamp > Time.utc - 5.seconds }

            if !new_errors.empty?
              socket.send(%({
                "type": "new_errors",
                "edge_id": "#{edge_id}",
                "errors": #{new_errors.to_json}
              }))
            end
          rescue e
            Log.error(exception: e) { "error in edge error stream" }
            break
          end
        end
      end

      socket.on_close do
        Log.info { {message: "edge error stream disconnected", edge_id: edge_id} }
      end
    end

    # WebSocket endpoint for real-time error monitoring of all edges
    @[AC::Route::WebSocket("/edges/errors/stream")]
    def all_edges_error_stream(socket) : Nil
      Log.info { "all edges error stream connected" }

      # Send initial state
      initial_health = module_manager.edge_health_status
      socket.send(%({
        "type": "initial_health",
        "edges": #{initial_health.to_json}
      }))

      # Keep connection alive and send periodic updates
      spawn do
        loop do
          sleep 3.seconds
          break if socket.closed?

          begin
            # Send health updates for all edges
            health_status = module_manager.edge_health_status
            socket.send(%({
              "type": "health_update_all",
              "timestamp": "#{Time.utc}",
              "edges": #{health_status.to_json}
            }))

            # Send recent errors from all edges
            all_errors = module_manager.edge_errors
            recent_errors = {} of String => Array(PlaceOS::Core::EdgeError)

            all_errors.each do |edge_id, errors|
              new_errors = errors.select { |error| error.timestamp > Time.utc - 3.seconds }
              recent_errors[edge_id] = new_errors unless new_errors.empty?
            end

            if !recent_errors.empty?
              socket.send(%({
                "type": "new_errors_all",
                "timestamp": "#{Time.utc}",
                "edges": #{recent_errors.to_json}
              }))
            end
          rescue e
            Log.error(exception: e) { "error in all edges error stream" }
            break
          end
        end
      end

      socket.on_close do
        Log.info { "all edges error stream disconnected" }
      end
    end

    # WebSocket endpoint for real-time module status monitoring
    @[AC::Route::WebSocket("/edges/modules/stream")]
    def edge_modules_stream(socket) : Nil
      Log.info { "edge modules stream connected" }

      # Send initial module status
      initial_status = module_manager.edge_module_status
      socket.send(%({
        "type": "initial_modules",
        "edges": #{initial_status.to_json}
      }))

      # Keep connection alive and send periodic updates
      spawn do
        loop do
          sleep 10.seconds
          break if socket.closed?

          begin
            # Send module status updates
            module_status = module_manager.edge_module_status
            socket.send(%({
              "type": "module_update_all",
              "timestamp": "#{Time.utc}",
              "edges": #{module_status.to_json}
            }))
          rescue e
            Log.error(exception: e) { "error in edge modules stream" }
            break
          end
        end
      end

      socket.on_close do
        Log.info { "edge modules stream disconnected" }
      end
    end

    # REST endpoint to trigger error cleanup
    @[AC::Route::POST("/cleanup")]
    def cleanup_errors(
      @[AC::Param::Info(description: "Hours to keep errors (default: 24)")]
      hours : Int32 = 24,
    ) : JSON::Any
      older_than = hours.hours
      module_manager.cleanup_old_edge_errors(older_than)

      JSON::Any.new({
        "success"   => JSON::Any.new(true),
        "message"   => JSON::Any.new("Cleaned up errors older than #{hours} hours"),
        "timestamp" => JSON::Any.new(Time.utc.to_s),
      })
    end

    # REST endpoint to get error summary
    @[AC::Route::GET("/summary")]
    def error_summary : JSON::Any
      health_status = module_manager.edge_health_status
      connection_status = module_manager.edge_connection_status

      JSON::Any.new({
        "total_edges"       => JSON::Any.new(health_status.size.to_i64),
        "connected_edges"   => JSON::Any.new(connection_status.count { |_, connected| connected }.to_i64),
        "edges_with_errors" => JSON::Any.new(health_status.count { |_, health| health.error_count_24h > 0 }.to_i64),
        "total_errors_24h"  => JSON::Any.new(health_status.sum { |_, health| health.error_count_24h }.to_i64),
        "total_modules"     => JSON::Any.new(health_status.sum { |_, health| health.module_count }.to_i64),
        "failed_modules"    => JSON::Any.new(health_status.sum { |_, health| health.failed_modules.size }.to_i64),
        "timestamp"         => JSON::Any.new(Time.utc.to_s),
      })
    end
  end
end
