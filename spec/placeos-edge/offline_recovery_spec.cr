require "./helper"
require "file_utils"

module PlaceOS::Edge
  describe "Offline Recovery Scenarios", tags: ["edge"] do
    it "recovers from extended offline period with large backlog" do
      dir = File.join(Dir.tempdir, "edge-offline-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        store = RuntimeStore.new(dir)

        # Simulate edge going offline with active modules
        snapshot = State::Snapshot.new(
          edge_id: "edge-offline-test",
          version: "v1",
          last_modified: Time.utc,
          drivers: [
            State::DesiredDriver.new("driver-meeting"),
            State::DesiredDriver.new("driver-camera"),
          ],
          modules: [
            State::DesiredModule.new("mod-room-1", "driver-meeting", true, %({"ip":"192.168.1.100"})),
            State::DesiredModule.new("mod-room-2", "driver-meeting", true, %({"ip":"192.168.1.101"})),
            State::DesiredModule.new("mod-cam-1", "driver-camera", true, %({"ip":"192.168.1.200"})),
          ]
        )

        store.save_snapshot(snapshot)
        store.save_runtime_module("mod-room-1", State::RuntimeModule.new("driver-meeting", loaded: true, running: true))
        store.save_runtime_module("mod-room-2", State::RuntimeModule.new("driver-meeting", loaded: true, running: true))
        store.save_runtime_module("mod-cam-1", State::RuntimeModule.new("driver-camera", loaded: true, running: true))

        # Simulate 500 redis updates while offline (realistic 1 hour offline scenario)
        updates = [] of State::PendingRedisUpdate
        500.times do |i|
          mod_id = "mod-room-#{(i % 2) + 1}"
          key = ["power", "volume", "muted", "input_source"][i % 4]
          value = ["true", "false", "50", "hdmi1"][i % 4]
          updates << store.queue_update(Protocol::RedisAction::HSET, "status/#{mod_id}", key, value)
        end

        # Simulate runtime events (different kinds to avoid full collapse)
        events = [] of State::PendingRuntimeEvent
        events << store.queue_event(State::RuntimeEvent.new(:driver_ready, driver_key: "driver-meeting"))
        events << store.queue_event(State::RuntimeEvent.new(:driver_ready, driver_key: "driver-camera"))
        events << store.queue_event(State::RuntimeEvent.new(:module_loaded, module_id: "mod-room-1", driver_key: "driver-meeting"))
        events << store.queue_event(State::RuntimeEvent.new(:module_loaded, module_id: "mod-room-2", driver_key: "driver-meeting"))
        events << store.queue_event(State::RuntimeEvent.new(:module_loaded, module_id: "mod-cam-1", driver_key: "driver-camera"))
        events << store.queue_event(State::RuntimeEvent.new(:module_started, module_id: "mod-room-1", driver_key: "driver-meeting"))
        events << store.queue_event(State::RuntimeEvent.new(:module_started, module_id: "mod-room-2", driver_key: "driver-meeting"))
        events << store.queue_event(State::RuntimeEvent.new(:module_started, module_id: "mod-cam-1", driver_key: "driver-camera"))
        events << store.queue_event(State::RuntimeEvent.new(:snapshot_applied, snapshot_version: "v1", backlog_depth: 500))
        # This will be collapsed with previous sync_status
        events << store.queue_event(State::RuntimeEvent.new(:sync_status, message: "offline", snapshot_version: "v1", backlog_depth: 500))

        store.flush

        # Verify state persisted
        store.pending_updates.size.should be > 0
        store.pending_events.size.should be > 0

        # Simulate edge restart (reload from disk)
        reloaded = RuntimeStore.new(dir)

        # Verify all state recovered
        reloaded.snapshot.not_nil!.version.should eq "v1"
        reloaded.snapshot.not_nil!.modules.size.should eq 3
        reloaded.runtime_modules.size.should eq 3
        reloaded.runtime_modules["mod-room-1"].running.should be_true
        reloaded.runtime_modules["mod-room-2"].running.should be_true
        reloaded.runtime_modules["mod-cam-1"].running.should be_true

        # Verify pending items recovered (collapsed duplicates)
        reloaded.pending_updates.size.should be < 500 # Collapsed
        reloaded.pending_events.size.should be <= 10  # May have some collapsed

        # Simulate coming back online - acknowledge all updates
        reloaded.pending_updates.each do |update|
          reloaded.acknowledge_update(update.id)
        end

        reloaded.pending_events.each do |event|
          reloaded.acknowledge_event(event.id)
        end

        # Verify queues cleared
        reloaded.pending_updates.should be_empty
        reloaded.pending_events.should be_empty

        # Verify compaction persisted
        reloaded.flush
        final = RuntimeStore.new(dir)
        final.pending_updates.should be_empty
        final.pending_events.should be_empty
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "handles disk full scenario gracefully" do
      dir = File.join(Dir.tempdir, "edge-diskfull-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        store = RuntimeStore.new(dir)

        snapshot = State::Snapshot.new(
          edge_id: "edge-test",
          version: "v1",
          last_modified: Time.utc,
          drivers: [State::DesiredDriver.new("driver-key")],
          modules: [State::DesiredModule.new("mod-1", "driver-key", true, %({"ip":"192.168.1.1"}))]
        )

        store.save_snapshot(snapshot)
        store.save_runtime_module("mod-1", State::RuntimeModule.new("driver-key", loaded: true, running: true))
        store.flush

        # Make directory read-only to simulate disk full
        File.chmod(File.join(dir, "edge-state"), 0o555)

        # Should not crash when trying to write (graceful degradation)
        # Edge continues in-memory only
        update = store.queue_update(Protocol::RedisAction::HSET, "status/mod-1", "power", "on")

        # In-memory state should be updated
        store.pending_updates.any?(&.id.==(update.id)).should be_true

        # But flush will fail silently (logged as warning)
        store.flush # This will fail but shouldn't crash

        # Verify edge still operational in-memory
        store.pending_updates.any?(&.id.==(update.id)).should be_true

        # Restore permissions
        File.chmod(File.join(dir, "edge-state"), 0o755)

        # Should work again after permissions restored
        update2 = store.queue_update(Protocol::RedisAction::HSET, "status/mod-1", "volume", "50")
        store.flush

        reloaded = RuntimeStore.new(dir)
        # First update was lost (couldn't write), second should be there
        reloaded.pending_updates.any?(&.id.==(update2.id)).should be_true
      ensure
        File.chmod(File.join(dir, "edge-state"), 0o755) rescue nil
        FileUtils.rm_rf(dir)
      end
    end

    it "handles rapid state changes with debouncing" do
      dir = File.join(Dir.tempdir, "edge-debounce-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        store = RuntimeStore.new(dir)

        snapshot = State::Snapshot.new(
          edge_id: "edge-test",
          version: "v1",
          last_modified: Time.utc,
          drivers: [State::DesiredDriver.new("driver-key")],
          modules: [State::DesiredModule.new("mod-1", "driver-key", true, %({"ip":"192.168.1.1"}))]
        )

        # Rapid updates (100 in quick succession)
        100.times do |i|
          store.save_snapshot(snapshot)
          store.save_runtime_module("mod-1", State::RuntimeModule.new("driver-key", loaded: true, running: (i % 2 == 0)))
        end

        # Wait for debounce to settle
        sleep 1.5.seconds

        # Should have written but not 100 times
        reloaded = RuntimeStore.new(dir)
        reloaded.snapshot.not_nil!.version.should eq "v1"
        reloaded.runtime_modules["mod-1"].should_not be_nil
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "handles backpressure limits correctly" do
      dir = File.join(Dir.tempdir, "edge-backpressure-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        store = RuntimeStore.new(dir)

        # Queue slightly more than max updates to test limit
        (Edge::MAX_PENDING_UPDATES + 100).times do |i|
          store.queue_update(Protocol::RedisAction::HSET, "status/mod-#{i}", "key", "value")
        end

        # Should be capped at max
        store.pending_updates.size.should eq Edge::MAX_PENDING_UPDATES

        # Queue slightly more than max events to test limit
        (Edge::MAX_PENDING_EVENTS + 50).times do |i|
          store.queue_event(State::RuntimeEvent.new(:module_started, module_id: "mod-#{i}", driver_key: "driver"))
        end

        # Should be capped at max
        store.pending_events.size.should eq Edge::MAX_PENDING_EVENTS

        store.flush

        # Verify limits persisted
        reloaded = RuntimeStore.new(dir)
        reloaded.pending_updates.size.should eq Edge::MAX_PENDING_UPDATES
        reloaded.pending_events.size.should eq Edge::MAX_PENDING_EVENTS
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "handles corrupted state files gracefully" do
      dir = File.join(Dir.tempdir, "edge-corrupt-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        Dir.mkdir_p(File.join(dir, "edge-state"))

        # Write corrupted core state
        File.write(File.join(dir, "edge-state", "core.json"), "{ invalid json }")

        # Write corrupted pending updates (mix of valid and invalid)
        File.write(File.join(dir, "edge-state", "pending-updates.jsonl"), <<-JSONL
        {"id":"valid-1","action":"hset","hash_id":"status/mod-1","key_name":"power","status_value":"on"}
        { invalid line }
        {"id":"valid-2","action":"hset","hash_id":"status/mod-2","key_name":"volume","status_value":"50"}
        JSONL
        )

        # Write corrupted pending events
        File.write(File.join(dir, "edge-state", "pending-events.jsonl"), <<-JSONL
        {"id":"event-1","event":{"timestamp":1234567890,"kind":"module_started","module_id":"mod-1","driver_key":"driver-key","message":null,"snapshot_version":null,"backlog_depth":null}}
        not json at all
        {"id":"event-2","event":{"timestamp":1234567891,"kind":"module_stopped","module_id":"mod-2","driver_key":"driver-key","message":null,"snapshot_version":null,"backlog_depth":null}}
        JSONL
        )

        # Should load without crashing, skipping invalid lines
        store = RuntimeStore.new(dir)

        # Core state should be empty (corrupted)
        store.snapshot.should be_nil

        # Should have loaded valid lines only
        store.pending_updates.size.should eq 2
        store.pending_updates.map(&.id).should contain("valid-1")
        store.pending_updates.map(&.id).should contain("valid-2")

        store.pending_events.size.should eq 2
        store.pending_events.map(&.id).should contain("event-1")
        store.pending_events.map(&.id).should contain("event-2")
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
