require "http"

require "./error"
require "./protocol"

require "simple_retry"

module PlaceOS::Edge
  # WebSocket Transport
  class Transport
    Log = ::Log.for(self)

    private getter! socket : HTTP::WebSocket
    private getter socket_lock : Mutex = Mutex.new

    private getter connection_errors = Channel(Exception).new

    private getter socket_channel = Channel(Protocol::Container).new
    private getter close_channel : Channel(Nil) = Channel(Nil).new

    private getter response_lock = RWLock.new
    private getter responses = {} of UInt64 => Channel(Protocol::Response)

    private getter on_request : {UInt64, ::PlaceOS::Edge::Protocol::Request} ->
    private getter on_disconnect : (IO::Error | HTTP::WebSocket::CloseCode ->)?

    private getter sequence_atomic : Atomic(UInt64)

    def initialize(
      sequence_id : UInt64 = 0,
      @on_disconnect : (Exception ->)? = nil,
      &@on_request : {UInt64, ::PlaceOS::Edge::Protocol::Request} ->
    )
      @sequence_atomic = Atomic(UInt64).new(sequence_id)
      spawn(same_thread: true) { write_websocket }
    end

    def sequence_id : UInt64
      sequence_atomic.add(1)
    end

    def closed?
      socket?.nil? || socket.closed?
    end

    def listen(socket : HTTP::WebSocket)
      run_socket(socket)
    rescue error
      on_disconnect.try &.call(error) if error.is_a?(IO::Error)
      disconnect
      raise error
    end

    def connect(uri : URI, socket : HTTP::WebSocket?)
      SimpleRetry.try_to(
        base_interval: 500.milliseconds,
        max_interval: 5.seconds
      ) do |_run_count, error|
        if error
          Log.warn { {error: error.to_s, message: "reconnecting"} }
          on_disconnect.try(&.call(error)) if error.is_a? IO::Error
          socket = nil
        end

        socket = socket || HTTP::WebSocket.new(uri)
        Log.debug { "core connection established" }
        run_socket(socket.as(HTTP::WebSocket)).run
        raise "rest api disconnected" unless close_channel.closed?
      end
    rescue error
      disconnect
      raise error
    end

    # Periodically send a ping frame
    #
    def ping(interval : Time::Span = 10.seconds)
      until close_channel.closed?
        socket_lock.synchronize do
          begin
            Log.debug { "keepalive ping sent" }
            socket?.try(&.ping)
          rescue
            Log.debug { "keepalive ping failed" }
          end
        end
        sleep(interval)
      end
    end

    def disconnect
      response_lock.synchronize do
        responses.each_value(&.close)
      end
      socket_channel.close
      close_channel.close
    end

    protected def run_socket(socket : HTTP::WebSocket)
      socket.on_message &->on_message(String)
      socket.on_binary &->on_binary(Bytes)
      socket.on_close do |close_code|
        on_disconnect.try(&.call(close_code))
      end

      socket_lock.synchronize do
        @socket = socket
      end
    end

    # Serialize messages down the websocket
    #
    protected def write_websocket
      while message = socket_channel.receive?
        return if message.nil?
        begin
          until !closed? || close_channel.closed?
            sleep 0.1
          end

          socket_lock.synchronize do
            case message
            in Protocol::Binary
              socket.stream(binary: true) do |io|
                message.to_io(io)
              end
            in Protocol::Text
              socket.send(message.to_json)
            end
          end
        rescue e
          connection_errors.send(e)
        end
      end
    end

    protected def send_response(id : UInt64, response : Protocol::Response)
      message = case response
                in Protocol::Message::Body
                  Protocol::Text.new(sequence_id: id, body: response)
                in Protocol::Message::BinaryBody
                  m = Protocol::Binary.new
                  m.sequence_id = id
                  m.status = response.success ? Protocol::Binary::Status::Success : Protocol::Binary::Status::Fail
                  m.key = response.key
                  m.path = response.path
                  m
                end

      socket_channel.send(message)
    end

    protected def send_request(request : Protocol::Request) : Protocol::Response?
      id = sequence_id

      response_channel = Channel(Protocol::Response).new
      response_lock.write do
        responses[id] = response_channel
      end

      socket_channel.send(Protocol::Text.new(sequence_id: id, body: request))

      select
      when response = response_channel.receive?
      when timeout 30.seconds
        raise Error::TransportTimeout.new(request)
      end

      response_lock.write do
        responses.delete(id)
      end

      response
    end

    private def on_message(message)
      handle_message(Protocol::Text.from_json(message))
    rescue e : JSON::ParseException
      Log.error(exception: e) { "failed to parse incoming message: #{message}" }
    end

    private def on_binary(bytes : Slice)
      handle_message(Protocol::Binary.from_slice(bytes))
    rescue e : BinData::ParseError
      Log.error(exception: e) { "failed to parse incoming binary message" }
    end

    private def handle_message(message : Protocol::Container)
      body, message_type = if message.is_a? Protocol::Binary
                             {Protocol::Message::BinaryBody.new(success: message.success, key: message.key, io: message.binary), "Binary"}
                           else
                             {message.body, message.body.type}
                           end

      case body
      in Protocol::Response
        response_lock.read do
          if channel = responses[message.sequence_id]?
            channel.send(body)
          else
            Log.error { {
              sequence_id: message.sequence_id.to_s,
              type:        message_type.to_s,
              message:     "unrequested response received",
            } }
          end
        end
      in Protocol::Request
        spawn(same_thread: true) do
          begin
            on_request.call({message.sequence_id, body})
          rescue e
            Log.error(exception: e) { {
              message:           e.message,
              sequence_id:       message.sequence_id.to_s,
              transport_message: body.to_json,
            } }
          end
        end
      end
    end
  end
end
