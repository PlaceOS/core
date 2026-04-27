require "http"
require "rwlock"

require "./protocol"
require "./transport"

require "../placeos-core/process_manager/edge"

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

      if edge = PlaceOS::Model::Edge.find?(edge_id)
        edge.update_fields(online: true, last_seen: Time.utc)
      end

      manager = nil.as(PlaceOS::Core::ProcessManager::Edge?)
      manager = PlaceOS::Core::ProcessManager::Edge.new(edge_id, socket, -> {
        active = false
        edges_lock.write do
          current = edges[edge_id]?
          active = current.same?(manager)
          edges.delete(edge_id) if active
        end
        manager.not_nil!.disconnected! if active
      })

      replaced = nil.as(PlaceOS::Core::ProcessManager::Edge?)
      edges_lock.write do
        replaced = edges[edge_id]?
        edges[edge_id] = manager.not_nil!
      end

      if stale = replaced
        begin
          stale.transport.disconnect
        rescue
          nil
        end
      end
    end

    # Look up `ProcessManager::Edge` for an edge_id
    #
    def for?(edge_id : String)
      if edge = edges_lock.read { edges[edge_id]? }
        edge
      else
        Log.debug { "no manager found for edge #{edge_id}" }
        nil
      end
    end

    # :ditto:
    def for?(edge_id : String, & : Core::ProcessManager::Edge ->)
      manager = for?(edge_id)
      yield manager unless manager.nil?
    end

    def runtime_status
      edges_lock.read do
        edges.transform_values(&.runtime_status)
      end
    end

    def stop : Nil
      managers = edges_lock.write do
        current = edges.values.dup
        edges.clear
        current
      end

      managers.each do |manager|
        begin
          manager.transport.disconnect
        rescue
          nil
        ensure
          manager.disconnected!
        end
      end
    end
  end
end
