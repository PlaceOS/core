require "./protocol"
require "./transport"

module PlaceOS::Edge
  class RealtimeChannel
    Log = ::Log.for(self)

    private getter uri : URI
    private getter secret : String
    private getter edge_id : String
    private getter ping_enabled : Bool
    private getter! transport : Transport
    @disconnecting = Atomic(Bool).new(false)

    def initialize(@uri : URI, @secret : String, @edge_id : String, @ping_enabled : Bool = true)
    end

    def connect(
      initial_socket : HTTP::WebSocket? = nil,
      on_disconnect : (IO::Error | HTTP::WebSocket::CloseCode ->)? = nil,
      on_connect : Proc(Nil)? = nil,
      &on_request : {UInt64, Protocol::Request} ->
    )
      @disconnecting.set(false)
      socket_uri = uri.dup
      socket_uri.path = Client::WEBSOCKET_API_PATH
      socket_uri.query = URI::Params.encode({"api-key" => secret, "edge_id" => edge_id})

      @transport = Transport.new(
        on_disconnect: on_disconnect,
        on_connect: on_connect,
      ) do |message|
        on_request.call(message)
      end

      spawn do
        begin
          transport.connect(socket_uri, initial_socket)
        rescue IO::Error | Channel::ClosedError
          nil
        rescue error
          Log.error(exception: error) { "realtime channel connect failed" } unless transport.closed? || @disconnecting.get
        end
      end

      while transport.closed?
        sleep 10.milliseconds
        Fiber.yield
      end

      if ping_enabled
        spawn do
          begin
            transport.ping
          rescue IO::Error | Channel::ClosedError
            nil
          rescue error
            Log.error(exception: error) { "realtime channel ping failed" } unless transport.closed? || @disconnecting.get
          end
        end
      end
    end

    def disconnect
      @disconnecting.set(true)
      transport.disconnect unless transport.closed?
    rescue
      nil
    end

    def closed?
      transport?.try(&.closed?) != false
    end

    def send_request(request : Protocol::Client::Request)
      transport.send_request(request)
    end

    def send_event(request : Protocol::Client::Request)
      transport.send_event(request)
    end

    def send_response(sequence_id : UInt64, response : Protocol::Client::Response | Protocol::Message::Success)
      transport.send_response(sequence_id, response)
    end
  end
end
