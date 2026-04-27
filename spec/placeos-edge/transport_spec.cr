require "./helper"

module PlaceOS::Edge
  private class TestTransport < Transport
    def send_request_public(request : Protocol::Request)
      send_request(request)
    end

    def send_event_public(request : Protocol::Request)
      send_event(request)
    end

    def send_response_public(id : UInt64, response : Protocol::Client::Response | Protocol::Message::BinaryBody | Protocol::Message::Success)
      send_response(id, response)
    end
  end

  describe Transport do
    it "routes requests to the on_request callback" do
      client_ws, server_ws = mock_sockets
      received = Channel(Tuple(UInt64, Protocol::Request)).new

      transport = TestTransport.new do |message|
        received.send(message)
      end

      server_ws.on_message do |message|
        client_ws.send(message)
      end

      begin
        spawn do
          transport.listen(client_ws)
          client_ws.run
        rescue IO::Error | Channel::ClosedError
          nil
        end

        spawn do
          server_ws.run
        rescue IO::Error | Channel::ClosedError
          nil
        end

        Fiber.yield

        server_ws.send(Protocol::Text.new(7_u64, Protocol::Message::Execute.new("mod-1", %({"ping":true}))).to_json)

        select
        when message = received.receive
          message[0].should eq 7_u64
          message[1].should be_a(Protocol::Message::Execute)
          request = message[1].as(Protocol::Message::Execute)
          request.module_id.should eq "mod-1"
          request.payload.should eq %({"ping":true})
        when timeout 2.seconds
          raise "timed out waiting for request callback"
        end
      ensure
        transport.disconnect
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end

    it "resolves responses for send_request" do
      client_ws, server_ws = mock_sockets

      transport = TestTransport.new { |_| }

      server_ws.on_message do |message|
        parsed = Protocol::Text.from_json(message)
        request = parsed.body.as(Protocol::Message::Execute)
        request.module_id.should eq "mod-2"

        response = Protocol::Text.new(
          parsed.sequence_id,
          Protocol::Message::ExecuteResponse.new(true, %("ok"), 200)
        )
        server_ws.send(response.to_json)
      end

      begin
        spawn do
          transport.listen(client_ws)
          client_ws.run
        rescue IO::Error | Channel::ClosedError
          nil
        end

        spawn do
          server_ws.run
        rescue IO::Error | Channel::ClosedError
          nil
        end

        Fiber.yield

        response = transport.send_request_public(Protocol::Message::Execute.new("mod-2", %({"value":1})))
        response.should be_a(Protocol::Message::ExecuteResponse)

        body = response.as(Protocol::Message::ExecuteResponse)
        body.success.should be_true
        body.output.should eq %("ok")
        body.code.should eq 200
      ensure
        transport.disconnect
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end

    it "sends fire-and-forget events without waiting for a response" do
      client_ws, server_ws = mock_sockets
      received = Channel(Protocol::Text).new

      transport = TestTransport.new { |_| }

      server_ws.on_message do |message|
        received.send(Protocol::Text.from_json(message))
      end

      begin
        spawn do
          transport.listen(client_ws)
          client_ws.run
        rescue IO::Error | Channel::ClosedError
          nil
        end

        spawn do
          server_ws.run
        rescue IO::Error | Channel::ClosedError
          nil
        end

        Fiber.yield

        transport.send_event_public(Protocol::Message::DebugMessage.new("mod-3", %([1,"hello"])))

        select
        when message = received.receive
          message.body.should be_a(Protocol::Message::DebugMessage)
          body = message.body.as(Protocol::Message::DebugMessage)
          body.module_id.should eq "mod-3"
          body.message.should eq %([1,"hello"])
        when timeout 2.seconds
          raise "timed out waiting for event delivery"
        end
      ensure
        transport.disconnect
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end

    it "returns nil if a request is made after disconnect" do
      transport = TestTransport.new { |_| }

      transport.disconnect
      response = transport.send_request_public(Protocol::Message::Execute.new("mod-4", %({"value":2})))
      response.should be_nil
    end

    it "releases a waiting request when disconnected before a response arrives" do
      client_ws, server_ws = mock_sockets
      transport = TestTransport.new { |_| }
      result = Channel(Protocol::Response | Nil).new

      server_ws.on_message do |_message|
      end

      begin
        spawn do
          transport.listen(client_ws)
          client_ws.run
        rescue IO::Error | Channel::ClosedError
          nil
        end

        run_mock_socket(server_ws)
        Fiber.yield

        spawn do
          result.send(transport.send_request_public(Protocol::Message::Execute.new("mod-5", %({"value":3}))))
        rescue IO::Error | Channel::ClosedError
          result.send(nil)
        end

        sleep 50.milliseconds
        transport.disconnect

        select
        when response = result.receive
          response.should be_nil
        when timeout 2.seconds
          raise "timed out waiting for request to be released on disconnect"
        end
      ensure
        transport.disconnect
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end

    it "routes binary responses to the waiting request" do
      client_ws, server_ws = mock_sockets
      transport = TestTransport.new { |_| }
      binary_path = File.join(Dir.tempdir, "edge-transport-binary-#{Random.rand(10_000)}")
      File.write(binary_path, "binary-payload")

      server_ws.on_message do |message|
        parsed = Protocol::Text.from_json(message)
        parsed.body.should be_a(Protocol::Message::FetchBinary)

        binary = Protocol::Binary.new
        binary.sequence_id = parsed.sequence_id
        binary.status = Protocol::Binary::Status::Success
        binary.key = "driver-key"
        binary.binary = IO::Memory.new("binary-payload")
        server_ws.stream(binary: true) do |io|
          io.write(binary.to_slice)
        end
      end

      begin
        spawn do
          transport.listen(client_ws)
          client_ws.run
        rescue IO::Error | Channel::ClosedError
          nil
        end

        run_mock_socket(server_ws)
        Fiber.yield

        response = transport.send_request_public(Protocol::Message::FetchBinary.new("driver-key"))
        response.should be_a(Protocol::Message::BinaryBody)

        body = response.as(Protocol::Message::BinaryBody)
        body.success.should be_true
        body.key.should eq "driver-key"
        body.io.gets_to_end.should eq "binary-payload"
      ensure
        File.delete(binary_path) rescue nil
        transport.disconnect
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end
  end
end
