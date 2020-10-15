require "retriable"
require "uri"
require "rwlock"

require "./protocol"

module PlaceOS::Edge
  class Client
    # Secret used to register with PlaceOS
    private EDGE_SECRET = ENV["PLACE_EDGE_SECRET"]? || abort "missing PLACE_EDGE_SECRET in environment"
    private PLACE_URI   = URI.parse(ENV["PLACE_URI"]? || abort "missing PLACE_HOST in environment")

    WEBSOCKET_API_PATH = "/edge"

    private getter transport : Transport?

    private getter uri : URI {
      PLACE_URI.path = edge
      PLACE_URI.query = "secret=#{EDGE_SECRET}"
      PLACE_URI
    }

    def initialize(@sequence_id : UInt64 = 0)
    end

    # Edge Specific
    ###############################################################################################

    # Initialize the WebSocket API
    #
    # Optionally accepts a block called after connection has been established.
    def start
      Retriable.retry do
        # Open a websocket
        @socket = HTTP::WebSocket.new(uri)

        close_channel = Channel(Nil).new

        @socket.on_close do
          Log.info { "websocket to #{PLACE_URI} closed" }
          close_channel.close
        end

        id = if existing_transport = transport
               existing_transport.sequence_id
             else
               0_u64
             end

        @transport = Transport.new(@socket, id) do |request|
          on_request(request)
        end

        spawn { socket.run }

        while socket.closed?
          Fiber.yield
        end

        yield

        close_channel.receive?
      end
    end

    # :ditto:
    def start
      start { }
    end

    def handshake
    end
  end
end
