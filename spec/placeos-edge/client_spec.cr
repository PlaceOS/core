require "./helper"

module PlaceOS::Edge
  describe Client, tags: ["api", "edge"] do
    it "handshakes on register" do
      coordination = Channel(Bool).new

      client = Client.new(binary_store: Build::Filesystem.new(Dir.tempdir))
      client_ws, server_ws = mock_sockets

      messages = Channel(Protocol::Text).new

      server_ws.on_message do |m|
        messages.send Protocol::Text.from_json(m)
        server_ws.send(Protocol::Text.new(0_u64, Protocol::Message::RegisterResponse.new(true)).to_json)
      end

      spawn do
        client.connect(client_ws) do
          coordination.send(true)
        end
      end

      spawn { server_ws.run }

      Fiber.yield

      select
      when message = messages.receive
      when timeout 60.seconds
        fail "timed out waiting for register request"
      end

      message.should_not be_nil
      message.body.should be_a(Protocol::Message::Register)

      body = message.body.as(Protocol::Message::Register)

      # Message should say what's on the edge currently
      # including modules and driver binaries
      body.modules.should be_empty
      body.drivers.should eq(client.drivers)

      select
      when result = coordination.receive
        result.should be_true
      when timeout 2.seconds
        fail "timed out waiting for edge client connection"
      end
    end
  end
end
