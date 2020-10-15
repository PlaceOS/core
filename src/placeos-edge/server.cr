require "http"
require "rwlock"

require "./protocol"
require "./transport"

module PlaceOS::Edge
  class Server
    Log = ::Log.for(self)

    private getter edges = {} of String => Transport
    private getter edges_lock = RWLock.new

    def initialize
    end

    def start
    end

    # Fulfil requests from an edge node
    def handle_request(edge_id : String, message : Protocol::Request)
    end

    def send_request(edge_id : String, message : Protocol::Request) : Protocol::Response?
      transport_for?(edge_id) do |transport|
        transport.send_request(message)
      end
    end

    def send_response(edge_id : String, message : Protocol::Response)
      transport_for?(edge_id) do |transport|
        transport.send_response(message)
      end
    end

    def add_edge(edge_id : String, socket : HTTP::WebSocket)
      socket.on_close do
        edges_lock.write do
          edges.delete(edge_id)
        end
      end

      socket.request do |request|
        handle_request(edge_id, request)
      end

      edges_lock.write do
        edges[edge_id] = socket
      end
    end

    def transport_for?(edge_id : String, & : Transport)
      if edge = edges_lock.read { edges[edge_id]? }
        yield edge
      else
        Log.error { "no transport found for edge #{edge_id}" }
      end
    end
  end
end
