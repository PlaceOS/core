require "./helper"

module PlaceOS::Edge
  describe Client do
    it "handshakes on register" do
      called = false
      coordination = Channel(Nil).new

      client = Client.new
      client_ws, server_ws = mock_sockets
      spawn {
        client.connect(client_ws) do
          called = true
          coordination.close
        end
      }

      messages = Channel(Protocol::Text).new

      server_ws.on_message do |m|
        messages.send Protocol::Text.from_json(m)
        server_ws.send(Protocol::Text.new(1_u64, Protocol::Message::RegisterResponse.new(true)).to_json)
      end

      spawn { server_ws.run }

      Fiber.yield

      select
      when message = messages.receive
      when timeout 2.seconds
        raise "timed out"
      end

      message.should_not be_nil
      message.body.should be_a(Protocol::Message::Register)

      body = message.body.as(Protocol::Message::Register)

      # Message should say what's on the edge currently
      # including modules and driver binaries
      body.modules.should be_empty
      body.drivers.should be_empty

      select
      when coordination.receive?
      when timeout 2.seconds
      end

      called.should be_true
    end
  end
end
