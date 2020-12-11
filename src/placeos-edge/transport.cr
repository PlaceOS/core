require "http"

require "./error"
require "./protocol"

module PlaceOS::Edge
  # WebSocket Transport
  #
  class Transport
    private getter! socket : HTTP::WebSocket
    private getter socket_lock : Mutex = Mutex.new
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
      spawn { write_websocket }
    end

    def sequence_id : UInt64
      sequence_atomic.add(1)
    end

    def listen(socket : HTTP::WebSocket)
      run_socket(socket)
    rescue error
      on_disconnect.try &.call(error) if error.is_a?(IO::Error)
      disconnect
      raise error
    end

    def connect(uri : URI, initial_socket : HTTP::WebSocket?)
      initial = initial_socket
      Retriable.retry(
        max_interval: 5.seconds,
        on_retry: ->(error : Exception, _i : Int32, _e : Time::Span, _p : Time::Span) {
          Log.warn { {error: error.to_s, message: "reconnecting"} }
          on_disconnect.try(&.call(error)) if error.is_a? IO::Error
          initial = nil
        }) do
        socket = initial || HTTP::WebSocket.new(uri)
        run_socket(socket.as(HTTP::WebSocket))
      end
    rescue error
      disconnect
      raise error
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

      errors = Channel(Exception).new

      spawn do
        begin
          socket.run
        rescue e
          errors.send(e)
        end
      end

      select
      when close_channel.receive?
      when error = errors.receive
        raise error
      end
    end

    # Serialize messages down the websocket
    #
    protected def write_websocket
      while message = socket_channel.receive?
        socket_lock.synchronize do
          case message
          in Protocol::Binary
            socket.stream(binary: true) do |io|
              message.as(Protocol::Binary).to_io(io)
            end
          in Protocol::Text
            socket.send(message.as(Protocol::Text).to_json)
          end
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
                  binary = response.binary || Bytes.empty
                  m.body = binary
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
      body = if message.is_a? Protocol::Binary
               Protocol::Message::BinaryBody.new(success: message.success, key: message.key, binary: message.body)
             else
               message.body
             end

      case body
      in Protocol::Response
        response_lock.read do
          if channel = responses[message.sequence_id]?
            channel.send(body.as(Protocol::Response))
          else
            Log.error { "unrequested response received: #{message.sequence_id}" }
          end
        end
      in Protocol::Request
        spawn do
          # TODO: remove casts once crystal correctly trims union here
          begin
            on_request.call({message.sequence_id, body}.as(Tuple(UInt64, Protocol::Request)))
          rescue e
            Log.error(exception: e) { {
              message:           e.message,
              sequence_id:       message.sequence_id.to_s,
              transport_message: body.as(Protocol::Request).to_json,
            } }
          end
        end
      end
    end
  end
end
