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

    private getter socket_channel = Channel(Protocol::Container).new
    private getter close_channel : Channel(Nil) = Channel(Nil).new

    private getter response_lock = RWLock.new
    private getter responses = {} of UInt64 => Channel(Protocol::Response)

    private getter on_request : {UInt64, ::PlaceOS::Edge::Protocol::Request} ->
    private getter on_disconnect : (IO::Error | HTTP::WebSocket::CloseCode ->)?
    private getter on_connect : Proc(Nil)?

    private getter sequence_atomic : Atomic(UInt64)
    private getter ping_failures : Int32 = 0

    def initialize(
      sequence_id : UInt64 = 0,
      @on_disconnect : (IO::Error | HTTP::WebSocket::CloseCode ->)? = nil,
      @on_connect : Proc(Nil)? = nil,
      &@on_request : {UInt64, ::PlaceOS::Edge::Protocol::Request} ->
    )
      @sequence_atomic = Atomic(UInt64).new(sequence_id)
      spawn { write_websocket }
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
      if socket
        Log.debug { "core connection established" }
        spawn { on_connect.try &.call } if on_connect
        run_socket(socket).run
        disconnect unless close_channel.closed?
        return
      end

      SimpleRetry.try_to(
        base_interval: 500.milliseconds,
        max_interval: 5.seconds
      ) do |_run_count, error|
        if error
          break if close_channel.closed?
          Log.warn { {error: error.to_s, message: "reconnecting"} }
          on_disconnect.try(&.call(error)) if error.is_a? IO::Error
          socket = nil
        end

        socket = socket || HTTP::WebSocket.new(uri)
        Log.debug { "core connection established" }
        spawn { on_connect.try &.call } if on_connect
        run_socket(socket.as(HTTP::WebSocket)).run
        break if close_channel.closed?
        raise "rest api disconnected"
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
            socket?.try(&.ping)
            @ping_failures = 0
          rescue
            @ping_failures += 1
            Log.debug { "keepalive ping failed #{@ping_failures} times" }

            # Log warning at 1 minute of failures
            if @ping_failures == 6
              Log.warn { "websocket connection appears to be down, reconnection in progress" }
            end

            # Only exit as last resort after ~10 minutes of continuous failures
            # This gives reconnection logic time to work
            if @ping_failures > 60
              Log.fatal { "websocket connection failed for 10+ minutes, restarting process..." }
              sleep(interval)
              exit(2)
            end
          end
        end
        sleep(interval)
      end
    end

    def disconnect
      socket_lock.synchronize do
        @socket.try(&.close) rescue nil
      end
      close_channel.close rescue nil
      socket_channel.close rescue nil
      response_lock.synchronize do
        responses.each_value(&.close) rescue nil
        responses.clear
      end
    rescue Channel::ClosedError
      nil
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
      # start processing messages
      while message = socket_channel.receive?
        return if message.nil?
        begin
          # sleep until we are ready to send messages
          # the transport can reconnect gracefully
          while closed?
            return if close_channel.closed?
            sleep 100.milliseconds
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
          Log.warn { {error: e.to_s, message: "write_websocket failed"} }
        end
      end
    end

    protected def send_response(id : UInt64, response : Protocol::Client::Response | Protocol::Message::BinaryBody | Protocol::Message::Success)
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
    rescue Channel::ClosedError
      nil
    end

    protected def send_request(request : Protocol::Request) : Protocol::Response?
      id = sequence_id

      response_channel = Channel(Protocol::Response).new
      response_lock.write do
        responses[id] = response_channel
      end

      begin
        socket_channel.send(Protocol::Text.new(sequence_id: id, body: request))
      rescue Channel::ClosedError
        response_lock.write do
          responses.delete(id)
        end
        return nil
      end

      response = select
      when received = response_channel.receive?
        received
      when timeout 30.seconds
        raise Error::TransportTimeout.new(request)
      end

      response_lock.write do
        responses.delete(id)
      end

      response
    end

    protected def send_event(request : Protocol::Request)
      socket_channel.send(Protocol::Text.new(sequence_id: sequence_id, body: request))
    rescue Channel::ClosedError
      nil
    ensure
      nil
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
            channel.send(body) rescue nil
          else
            Log.error { {
              sequence_id: message.sequence_id.to_s,
              type:        message_type.to_s,
              message:     "unrequested response received",
            } }
          end
        end
      in Protocol::Request
        spawn do
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
