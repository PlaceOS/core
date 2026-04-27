require "./helper"

module PlaceOS::Edge
  describe Server do
    it "registers and exposes an edge manager while the socket is open" do
      client_ws, server_ws = mock_sockets
      edge = PlaceOS::Model::Generator.edge.save!
      server = Server.new

      begin
        server.manage_edge(edge.id.as(String), server_ws)

        manager = server.for?(edge.id.as(String))
        manager.should_not be_nil
        manager.not_nil!.edge_id.should eq edge.id

        status = server.runtime_status[edge.id.as(String)]?
        status.should_not be_nil
        status.not_nil!.connected.should be_true

        edge.reload!
        edge.online.should be_true
        edge.last_seen.should_not be_nil
      ensure
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end

    it "removes the edge manager and marks the edge disconnected on socket close" do
      client_ws, server_ws = mock_sockets
      edge = PlaceOS::Model::Generator.edge.save!
      server = Server.new

      begin
        server.manage_edge(edge.id.as(String), server_ws)
        server.for?(edge.id.as(String)).should_not be_nil

        run_mock_socket(server_ws)
        run_mock_socket(client_ws)

        Fiber.yield

        client_ws.close

        deadline = Time.instant + 2.seconds
        until server.for?(edge.id.as(String)).nil?
          raise "timed out waiting for edge manager removal" if Time.instant >= deadline
          sleep 10.milliseconds
        end

        server.for?(edge.id.as(String)).should be_nil

        edge.reload!
        edge.online.should be_false

        status = server.runtime_status[edge.id.as(String)]?
        status.should be_nil
      ensure
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end

    it "updates runtime status from heartbeat messages" do
      client_ws, server_ws = mock_sockets
      edge = PlaceOS::Model::Generator.edge.save!
      server = Server.new

      begin
        server.manage_edge(edge.id.as(String), server_ws)
        run_mock_socket(server_ws)
        run_mock_socket(client_ws)
        Fiber.yield

        heartbeat = Protocol::Text.new(
          11_u64,
          Protocol::Message::Heartbeat.new(
            Time.utc,
            "snapshot-123",
            4,
            2
          )
        )
        client_ws.send(heartbeat.to_json)

        deadline = Time.instant + 2.seconds
        loop do
          status = server.runtime_status[edge.id.as(String)]?
          break if status && status.snapshot_version == "snapshot-123" && status.pending_updates == 4 && status.pending_events == 2 && status.last_event == "heartbeat"
          raise "timed out waiting for heartbeat status update" if Time.instant >= deadline
          sleep 10.milliseconds
        end

        status = server.runtime_status[edge.id.as(String)].not_nil!
        status.connected.should be_true
        status.snapshot_version.should eq "snapshot-123"
        status.pending_updates.should eq 4
        status.pending_events.should eq 2
        status.last_event.should eq "heartbeat"
      ensure
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end

    it "updates runtime status from runtime events and records sync errors" do
      client_ws, server_ws = mock_sockets
      edge = PlaceOS::Model::Generator.edge.save!
      server = Server.new

      begin
        server.manage_edge(edge.id.as(String), server_ws)
        run_mock_socket(server_ws)
        run_mock_socket(client_ws)
        Fiber.yield

        event = Protocol::Text.new(
          12_u64,
          Protocol::Message::RuntimeEvent.new(
            "sync_status",
            nil,
            nil,
            "connection dropped",
            "snapshot-err",
            7
          )
        )
        client_ws.send(event.to_json)

        deadline = Time.instant + 2.seconds
        loop do
          status = server.runtime_status[edge.id.as(String)]?
          break if status && status.last_event == "sync_status" && status.last_error == "connection dropped"
          raise "timed out waiting for runtime event status update" if Time.instant >= deadline
          sleep 10.milliseconds
        end

        status = server.runtime_status[edge.id.as(String)].not_nil!
        status.connected.should be_true
        status.snapshot_version.should eq "snapshot-err"
        status.pending_updates.should eq 7
        status.last_event.should eq "sync_status"
        status.last_error.should eq "connection dropped"
      ensure
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end

    it "keeps the replacement manager when an older connection closes later" do
      client_ws_1, server_ws_1 = mock_sockets
      client_ws_2, server_ws_2 = mock_sockets
      edge = PlaceOS::Model::Generator.edge.save!
      server = Server.new

      begin
        server.manage_edge(edge.id.as(String), server_ws_1)
        original = server.for?(edge.id.as(String)).not_nil!

        server.manage_edge(edge.id.as(String), server_ws_2)
        replacement = server.for?(edge.id.as(String)).not_nil!
        replacement.same?(original).should be_false

        run_mock_socket(server_ws_1)
        run_mock_socket(client_ws_1)
        run_mock_socket(server_ws_2)
        run_mock_socket(client_ws_2)
        Fiber.yield

        client_ws_1.close
        sleep 100.milliseconds

        current = server.for?(edge.id.as(String))
        current.should_not be_nil
        current.should eq replacement

        edge.reload!
        edge.online.should be_true
      ensure
        client_ws_1.close rescue nil
        server_ws_1.close rescue nil
        client_ws_2.close rescue nil
        server_ws_2.close rescue nil
      end
    end
  end
end
