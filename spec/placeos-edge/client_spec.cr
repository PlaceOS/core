require "./helper"
require "../processes/support"
require "file_utils"

module PlaceOS::Edge
  class Client
    def __test_load_persisted_snapshot
      load_persisted_snapshot
    end

    def __test_connect_sync_count
      @connect_sync_count.get
    end
  end

  describe Client, tags: ["api", "edge"] do
    it "responds to execute requests over the realtime websocket without a register handshake" do
      PlaceOS::Core::ProcessManager.with_driver do |mod, driver_path, driver_key, _driver|
        client = Client.new(skip_handshake: true, ping: false)
        client_ws, server_ws = mock_sockets
        begin
          module_id = mod.id.as(String)
          client.runtime_manager.load(module_id, driver_key)
          client.runtime_manager.start(module_id, PlaceOS::Core::ModuleManager.start_payload(mod))

          response_channel = Channel(Protocol::Text).new

          server_ws.on_message do |message|
            parsed = Protocol::Text.from_json(message)
            case parsed.body
            when Protocol::Message::ProxyRedis, Protocol::Message::RuntimeEvent, Protocol::Message::Heartbeat
              server_ws.send(Protocol::Text.new(parsed.sequence_id, Protocol::Message::Success.new(true)).to_json)
            else
              response_channel.send parsed
            end
          end

          spawn do
            client.connect(client_ws)
          rescue IO::Error | Channel::ClosedError
            nil
          end
          spawn do
            server_ws.run
          rescue IO::Error | Channel::ClosedError
            nil
          end
          Fiber.yield

          request = Protocol::Text.new(
            42_u64,
            Protocol::Message::Execute.new(
              module_id: module_id,
              payload: PlaceOS::Core::ModuleManager.execute_payload(:used_for_place_testing),
              user_id: nil
            )
          )

          server_ws.send(request.to_json)

          deadline = Time.instant + 2.seconds
          loop do
            raise "timed out waiting for execute response" if Time.instant >= deadline

            select
            when response = response_channel.receive
              next unless response.sequence_id == 42_u64
              response.body.should be_a(Protocol::Message::ExecuteResponse)

              body = response.body.as(Protocol::Message::ExecuteResponse)
              body.success.should be_true
              body.output.should eq %("you can delete this file")
              body.code.should eq 200
              break
            when timeout 50.milliseconds
            end
          end
        ensure
          client.runtime_manager.kill(driver_key) rescue nil
          client.disconnect
          client_ws.close rescue nil
          server_ws.close rescue nil
        end
      end
    end

    it "forwards debug messages and stops after ignore over the realtime websocket" do
      PlaceOS::Core::ProcessManager.with_driver do |mod, _driver_path, driver_key, _driver|
        client = Client.new(skip_handshake: true, ping: false)
        client_ws, server_ws = mock_sockets
        begin
          module_id = mod.id.as(String)
          client.runtime_manager.load(module_id, driver_key)
          client.runtime_manager.start(module_id, PlaceOS::Core::ModuleManager.start_payload(mod))

          received = Channel(Protocol::Text).new

          server_ws.on_message do |message|
            parsed = Protocol::Text.from_json(message)

            body = parsed.body
            case body
            when Protocol::Message::Debug
              server_ws.send(Protocol::Text.new(parsed.sequence_id, Protocol::Message::Success.new(true)).to_json)
              received.send(parsed)
            when Protocol::Message::Ignore
              server_ws.send(Protocol::Text.new(parsed.sequence_id, Protocol::Message::Success.new(true)).to_json)
              received.send(parsed)
            when Protocol::Message::ProxyRedis, Protocol::Message::RuntimeEvent, Protocol::Message::Heartbeat
              server_ws.send(Protocol::Text.new(parsed.sequence_id, Protocol::Message::Success.new(true)).to_json)
            else
              received.send(parsed)
            end
          end

          spawn do
            client.connect(client_ws)
          rescue IO::Error | Channel::ClosedError
            nil
          end
          spawn do
            server_ws.run
          rescue IO::Error | Channel::ClosedError
            nil
          end
          Fiber.yield

          server_ws.send(Protocol::Text.new(1_u64, Protocol::Message::Debug.new(module_id)).to_json)

          select
          when response = received.receive
            response.body.should be_a(Protocol::Message::Success)
            response.sequence_id.should eq 1_u64
          when timeout 2.seconds
            raise "timed out waiting for debug subscription"
          end

          # Drain initial status chatter before triggering the explicit debug output.
          loop do
            select
            when message = received.receive
              break if message.body.is_a?(Protocol::Message::DebugMessage)
            when timeout 200.milliseconds
              break
            end
          end

          result, code = client.runtime_manager.execute(
            module_id,
            PlaceOS::Core::ModuleManager.execute_payload(:echo, ["hello"]),
            user_id: nil
          )
          result.should eq %("hello")
          code.should eq 200

          messages = [] of String
          6.times do
            select
            when message = received.receive
              next unless body = message.body.as?(Protocol::Message::DebugMessage)
              messages << body.message
              break if body.message == %([1,"hello"])
            when timeout 2.seconds
              break
            end
          end
          messages.should contain %([1,"hello"])

          server_ws.send(Protocol::Text.new(2_u64, Protocol::Message::Ignore.new(module_id)).to_json)

          select
          when response = received.receive
            response.body.should be_a(Protocol::Message::Success)
            response.sequence_id.should eq 2_u64
          when timeout 2.seconds
            raise "timed out waiting for ignore request"
          end

          client.runtime_manager.execute(
            module_id,
            PlaceOS::Core::ModuleManager.execute_payload(:echo, ["hello"]),
            user_id: nil
          )

          expect_raises(Exception) do
            loop do
              select
              when message = received.receive
                if body = message.body.as?(Protocol::Message::DebugMessage)
                  raise "unexpected debug message after ignore: #{body.message}"
                end
              when timeout 500.milliseconds
                raise "timeout"
              end
            end
          end
        ensure
          client.runtime_manager.kill(driver_key) rescue nil
          client.disconnect
          client_ws.close rescue nil
          server_ws.close rescue nil
        end
      end
    end

    it "flushes queued redis updates, runtime events, and heartbeat state when the websocket connects" do
      client = nil.as(Client?)
      client_ws, server_ws = mock_sockets
      dir = File.join(Dir.tempdir, "edge-client-store-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        store = RuntimeStore.new(dir)
        client = Client.new(skip_handshake: true, ping: false, sync_injected_socket: true, runtime_store: store)

        store.save_snapshot(
          State::Snapshot.new(
            edge_id: "edge-test",
            version: "snapshot-42",
            last_modified: Time.utc,
            drivers: [] of State::DesiredDriver,
            modules: [] of State::DesiredModule
          )
        )
        queued_update = store.queue_update(Protocol::RedisAction::HSET, "status/mod-1", "power", "on")
        queued_event = store.queue_event(State::RuntimeEvent.new(:sync_status, message: "offline", snapshot_version: "snapshot-42", backlog_depth: 1))

        received = Channel(Protocol::Text).new

        server_ws.on_message do |message|
          parsed = Protocol::Text.from_json(message)
          received.send(parsed)

          case body = parsed.body
          when Protocol::Message::ProxyRedis, Protocol::Message::RuntimeEvent, Protocol::Message::Heartbeat
            server_ws.send(Protocol::Text.new(parsed.sequence_id, Protocol::Message::Success.new(true)).to_json)
          end
        end

        spawn do
          client.connect(client_ws)
        rescue IO::Error | Channel::ClosedError
          nil
        end
        run_mock_socket(server_ws)
        Fiber.yield

        seen_types = [] of Protocol::Message::Body::Type
        deadline = Time.instant + 2.seconds
        until seen_types.includes?(Protocol::Message::Body::Type::ProxyRedis) &&
              seen_types.includes?(Protocol::Message::Body::Type::RuntimeEvent) &&
              seen_types.includes?(Protocol::Message::Body::Type::Heartbeat)
          raise "timed out waiting for queued sync traffic flush" if Time.instant >= deadline

          select
          when message = received.receive
            seen_types << message.body.type
          when timeout 50.milliseconds
          end
        end

        store.pending_updates.any?(&.id.==(queued_update.id)).should be_false
        store.pending_events.any?(&.id.==(queued_event.id)).should be_false

        deadline = Time.instant + 2.seconds
        until client.__test_connect_sync_count > 0
          raise "timed out waiting for connect sync completion" if Time.instant >= deadline
          sleep 10.milliseconds
        end
      ensure
        client.try &.disconnect
        client_ws.close rescue nil
        server_ws.close rescue nil
        FileUtils.rm_rf(dir)
      end
    end

    it "boots runtime state from the persisted snapshot without websocket orchestration" do
      PlaceOS::Core::ProcessManager.with_driver do |mod, _driver_path, driver_key, _driver|
        client = nil.as(Client?)
        dir = File.join(Dir.tempdir, "edge-client-store-#{UUID.random}")
        begin
          Dir.mkdir_p(dir)
          store = RuntimeStore.new(dir)
          client = Client.new(skip_handshake: true, ping: false, runtime_store: store)

          snapshot = State::Snapshot.new(
            edge_id: "edge-test",
            version: "persisted-v1",
            last_modified: Time.utc,
            drivers: [State::DesiredDriver.new(driver_key)],
            modules: [State::DesiredModule.new(
              mod.id.as(String),
              driver_key,
              true,
              PlaceOS::Core::ModuleManager.start_payload(mod)
            )]
          )
          store.save_snapshot(snapshot)

          client.__test_load_persisted_snapshot

          client.driver_loaded?(driver_key).should be_true
          client.module_loaded?(mod.id.as(String)).should be_true
          store.last_snapshot_version.should eq "persisted-v1"
        ensure
          client.try &.runtime_manager.kill(driver_key)
          FileUtils.rm_rf(dir)
        end
      end
    end
  end
end
