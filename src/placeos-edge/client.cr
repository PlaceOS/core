require "retriable"
require "uri"
require "rwlock"

require "./constants"
require "./protocol"
require "./transport"

module PlaceOS::Edge
  class Client
    Log                = ::Log.for(self)
    WEBSOCKET_API_PATH = "/edge"

    private getter transport : Transport?
    private getter! uri : URI

    def initialize(
      uri : URI = PLACE_URI,
      secret : String = CLIENT_SECRET,
      @sequence_id : UInt64 = 0
    )
      # Mutate a copy as secret is embedded in uri
      uri = uri.dup
      uri.path = WEBSOCKET_API_PATH
      uri.query = "secret=#{secret}"
      @uri = uri
    end

    # Initialize the WebSocket API
    #
    # Optionally accepts a block called after connection has been established.
    def start(initial_socket : HTTP::WebSocket? = nil)
      socket = initial_socket || HTTP::WebSocket.new(uri)
      Retriable.retry(on_retry: ->(_ex : Exception, _i : Int32, _e : Time::Span, _p : Time::Span) { socket = HTTP::WebSocket.new(uri) }) do
        close_channel = Channel(Nil).new

        socket.on_close do
          Log.info { "websocket to #{PLACE_URI} closed" }
          close_channel.close
        end

        id = if existing_transport = transport
               existing_transport.sequence_id
             else
               0_u64
             end

        @transport = Transport.new(socket, id) do |(sequence_id, request)|
          case request
          in Protocol::Server::Request
            handle_request(sequence_id, request)
          in Protocol::Client::Request
            Log.error { "unexpected request received #{request.inspect}" }
          end
        end

        spawn { socket.as(HTTP::WebSocket).run }

        while socket.closed?
          Fiber.yield
        end

        handshake

        yield

        close_channel.receive?
      end
    end

    # :ditto:
    def start(initial_socket : HTTP::WebSocket? = nil)
      start(initial_socket) { }
    end

    def handle_request(sequence_id : UInt64, request : Protocol::Server::Request)
    end

    def send_request(request : Protocol::Client::Request) : Protocol::Server::Response
      t = transport
      if t.nil?
        raise "cannot send request over closed transport"
      else
        t.send_request(request).as(Protocol::Server::Response)
      end
    end

    # TODO: fix up this client. would be good to get the correct type back

    def handshake
      Retriable.retry do
        unless send_request(Protocol::Register.new).success
          Log.warn { "failed to register to core" }
          raise "handshake failed"
        end
      end
    end
  end
end
