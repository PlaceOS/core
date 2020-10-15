require "http"
require "rwlock"

require "./protocol"

module PlaceOS::Edge
  class Server
    private getter sockets = {} of String => HTTP::WebSocket
    private getter sockets_lock = RWLock.new

    def on_message(edge_id, message)
      handle_message(edge_id, Text.from_json(message))
    rescue e : JSON::ParseException
      Log.error(exception: e) { {
        edge_id: edge_id,
        message: "failed to parse incoming message from an edge",
      } }
    end

    def on_close(edge_id)
      sockets_lock.write do
        sockets.delete(edge_id)
      end
    end

    def add_edge(edge_id : String, socket : HTTP::WebSocket)
      socket.on_close { on_close(edge_id) }

      socket.on_message do |payload|
        on_message(edge_id, payload)
      end

      sockets_lock.write do
        sockets[edge_id] = socket
      end
    end

    def handle_message(edge_id : String, message : Protocol::Text)
    end

    protected def start_event_loop
    end
  end
end
