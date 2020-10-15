require "./protocol"

module PlaceOS::Edge

  # WebSocket Transport
  #
  class Transport
    private getter socket : HTTP::WebSocket

    private getter socket_channel = Channel(Protocol::Message)

    private getter response_lock = RWLock.new

    private getter responses = {} of String => Channel(Protocol::Response)

    private getter sequence_lock = Mutex.new

    private getter on_request : Protocol::Message ->

    def initialize(@socket, @sequence_id : UInt64 = 0, &@on_request : Protocol::Request ->)
      @socket.on_message &->on_message(String)
      @socket.on_binary &->on_message(String)
      spawn { write_websocket }
    end

    def sequence_id : UInt64
      sequence_lock.synchronize { @sequence_id += 1 }
    end

    # Serialize messages down the websocket
    #
    protected def write_websocket
      while message = socket_channel.receive?
        case message
        in Binary
          socket.stream(binary: true) do |io|
            message.to_io(io)
          end
        in Text
          socket.send(message.to_json)
        end
      end
    end

    def send_response(message : Protocol::Response)
      socket_channel.send(message)
    end

    def send_request(message : Protocol::Request) : Protocol::Response?
      id = sequence_id
      response_channel = Channel(Protocol::Message)
      response_lock.synchronize do
        responses[id] = response_channel
      end

      socket_channel.send(message)

      response = response_channel.receive?

      response_lock.synchronize do
        responses.delete(id)
      end

      response
    end

    private def on_message(message)
      handle_message(Protocol::Text.from_json(message))
    rescue e : JSON::ParseException
      Log.error(exception: e) { "failed to parse incoming message: #{message}" }
    end

    private def on_binary(io)
      handle_message(io.read_bytes(Protocol::Binary))
    rescue e : BinData::ParseError
      Log.error(exception: e) { "failed to parse incoming binary message" }
    end

    private def handle_message(message : Protocol::Message)
      case message
      in Response
        response_lock.synchronise do
          if channel = responses[message.sequence_id]?
            channel.send(message)
          else
            Log.error { "unrequested response received: #{message.sequence_id}" }
          end
        end
      in Request
        on_request.call(message)
      end
    end
  end
end
