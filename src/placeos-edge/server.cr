require "http"
require "rwlock"

require "./protocol"

module PlaceOS::Edge
  class Server
    private getter sockets = {} of String => HTTP::WebSocket
    private getter sockets_lock = RWLock.new

    def initialiaze
      handshake
      start_event_loop
    end

    def add_edge(edge_id : String, socket : HTTP::WebSocket)
      socket.on_close { remove_edge(edge_id) }
      socket.on_message { |message| handle_edge_message(edge_id, message) }

      sockets_lock.write do
        sockets[edge_id] = socket
      end
    end

    def handle_edge_message(edge_id : String, message : String)

    rescue e : JSON::ParseException
      Log.error(exception: e) { {
        edge_id: edge_id,
        message: "failed to parse incoming message from an edge",
      } }
    end

    def remove_edge(edge_id : String)
      sockets_lock.write do
        sockets.delete(edge_id)
      end
    end

    protected def start_event_loop
    end
  end
end
