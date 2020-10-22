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
        edges.transform_values &.{{call.name.id}}
      end
    end

    # Maintains an Edge API, cleaning up after the socket closes
    #
    def manage(edge_id : String, socket : HTTP::WebSocket)
      socket.on_close do
        edges_lock.write do
          edges.delete(edge_id)
        end
      end

      manager = ProcessManager::Edge.new(socket)

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
    def for?(edge_id : String, & : ProcessManager::Edge)
      manager = for?(edge_id)
      yield manager unless manager.nil?
    end
  end
end
