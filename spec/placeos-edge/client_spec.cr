require "./helper"

module PlaceOS::Edge
  describe Client, tags: ["api", "edge"] do
    it "handshakes on register" do
      coordination = Channel(Bool).new

      client = Client.new
      client_ws, server_ws = mock_sockets

      spawn {
        client.connect(client_ws) do
          coordination.send(true)
        end
      }

      messages = Channel(Protocol::Text).new

      server_ws.on_message do |m|
        messages.send Protocol::Text.from_json(m)
        server_ws.send(Protocol::Text.new(0_u64, Protocol::Message::RegisterResponse.new(true)).to_json)
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
      body.drivers.should eq(client.drivers)

      select
      when result = coordination.receive
        result.should be_true
      when timeout 2.seconds
        raise "timed out"
      end
    end

    it "sends error and health reports" do
      client = Client.new
      client_ws, server_ws = mock_sockets

      error_reports = Channel(Protocol::Message::ErrorReport).new
      health_reports = Channel(Protocol::Message::HealthReport).new

      server_ws.on_message do |m|
        message = Protocol::Text.from_json(m)
        case message.body
        when Protocol::Message::Register
          # Respond to registration
          server_ws.send(Protocol::Text.new(message.sequence_id, Protocol::Message::RegisterResponse.new(true)).to_json)
        when Protocol::Message::ErrorReport
          error_reports.send(message.body.as(Protocol::Message::ErrorReport))
          server_ws.send(Protocol::Text.new(message.sequence_id, Protocol::Message::Success.new(true)).to_json)
        when Protocol::Message::HealthReport
          health_reports.send(message.body.as(Protocol::Message::HealthReport))
          server_ws.send(Protocol::Text.new(message.sequence_id, Protocol::Message::Success.new(true)).to_json)
        end
      end

      spawn { server_ws.run }

      spawn {
        client.connect(client_ws) do
          # Track an error to trigger immediate reporting
          client.track_error(
            PlaceOS::Core::ErrorType::ModuleExecution,
            "Test error message",
            {"test" => "context"},
            PlaceOS::Core::Severity::Critical
          )
        end
      }

      Fiber.yield
      sleep 0.1 # Give time for immediate error report

      # Should receive an immediate error report for critical error
      select
      when error_report = error_reports.receive
        error_report.edge_id.should_not be_empty
        error_report.errors.size.should eq(1)

        # Parse the error JSON
        error_json = error_report.errors.first
        error = PlaceOS::Core::EdgeError.from_json(error_json)
        error.error_type.should eq(PlaceOS::Core::ErrorType::ModuleExecution)
        error.message.should eq("Test error message")
        error.severity.should eq(PlaceOS::Core::Severity::Critical)
      when timeout 2.seconds
        raise "timed out waiting for error report"
      end

      # Should also receive periodic health reports (though we won't wait for the full interval)
      # We can test the health report generation directly
      health = client.get_edge_health
      health.edge_id.should_not be_empty
      health.connected.should be_true
      health.module_count.should eq(0)    # No modules loaded in test
      health.error_count_24h.should eq(1) # One error tracked
    end
  end
end
