require "./helper"
require "file_utils"

module PlaceOS::Edge
  describe RuntimeStore, tags: ["edge"] do
    it "persists snapshots and queued redis updates" do
      dir = File.join(Dir.tempdir, "edge-runtime-store-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        store = RuntimeStore.new(dir)

        snapshot = State::Snapshot.new(
          edge_id: "edge-123",
          version: "v1",
          last_modified: Time.utc,
          drivers: [State::DesiredDriver.new("driver-key")],
          modules: [State::DesiredModule.new("mod-1", "driver-key", true, %({"name":"demo"}))]
        )

        store.save_snapshot(snapshot)
        update = store.queue_update(Protocol::RedisAction::HSET, "status/mod-1", "power", "on")
        pending_event = store.queue_event(State::RuntimeEvent.new(:sync_status, message: "offline", backlog_depth: 1))
        store.save_runtime_module("mod-1", State::RuntimeModule.new("driver-key", loaded: true, running: true, payload: "{}"))

        # Flush to ensure all writes complete before reloading
        store.flush

        reloaded = RuntimeStore.new(dir)
        reloaded.snapshot.not_nil!.version.should eq "v1"
        reloaded.runtime_modules["mod-1"].running.should be_true
        reloaded.pending_updates.first.id.should eq update.id
        reloaded.pending_events.first.id.should eq pending_event.id
        reloaded.last_error.should be_nil

        reloaded.acknowledge_update(update.id)
        reloaded.acknowledge_event(pending_event.id)
        reloaded.pending_updates.should be_empty
        reloaded.pending_events.should be_empty
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "collapses repeated latest-value redis updates and sync status events" do
      dir = File.join(Dir.tempdir, "edge-runtime-store-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        store = RuntimeStore.new(dir)

        first = store.queue_update(Protocol::RedisAction::HSET, "status/mod-1", "power", "off")
        second = store.queue_update(Protocol::RedisAction::HSET, "status/mod-1", "power", "on")
        store.queue_update(Protocol::RedisAction::PUBLISH, "status/mod-1", "event", "hello")

        pending_updates = store.pending_updates
        pending_updates.size.should eq 2
        pending_updates.any?(&.id.==(first.id)).should be_false
        pending_updates.any?(&.id.==(second.id)).should be_true
        pending_updates.find(&.action.publish?).not_nil!.status_value.should eq "hello"

        old_sync = store.queue_event(State::RuntimeEvent.new(:sync_status, message: "offline"))
        new_sync = store.queue_event(State::RuntimeEvent.new(:sync_status, message: "online"))
        store.queue_event(State::RuntimeEvent.new(:module_started, module_id: "mod-1", driver_key: "driver-key"))

        pending_events = store.pending_events
        pending_events.size.should eq 2
        pending_events.any?(&.id.==(old_sync.id)).should be_false
        pending_events.any?(&.id.==(new_sync.id)).should be_true
        pending_events.find(&.event.kind.sync_status?).not_nil!.event.message.should eq "online"
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "uses separate files for core state and pending items" do
      dir = File.join(Dir.tempdir, "edge-runtime-store-#{UUID.random}")
      begin
        Dir.mkdir_p(dir)
        store = RuntimeStore.new(dir)

        snapshot = State::Snapshot.new(
          edge_id: "edge-123",
          version: "v1",
          last_modified: Time.utc,
          drivers: [State::DesiredDriver.new("driver-key")],
          modules: [State::DesiredModule.new("mod-1", "driver-key", true, %({"name":"demo"}))]
        )

        store.save_snapshot(snapshot)
        store.queue_update(Protocol::RedisAction::HSET, "status/mod-1", "power", "on")
        store.queue_update(Protocol::RedisAction::HSET, "status/mod-1", "volume", "50")
        store.queue_event(State::RuntimeEvent.new(:module_started, module_id: "mod-1", driver_key: "driver-key"))
        store.flush

        # Verify separate files exist
        state_dir = File.join(dir, "edge-state")
        Dir.exists?(state_dir).should be_true
        File.exists?(File.join(state_dir, "core.json")).should be_true
        File.exists?(File.join(state_dir, "pending-updates.jsonl")).should be_true
        File.exists?(File.join(state_dir, "pending-events.jsonl")).should be_true

        # Verify core state file is small (doesn't contain pending items)
        core_content = File.read(File.join(state_dir, "core.json"))
        core_json = JSON.parse(core_content)
        core_json["pending_updates"].as_a.should be_empty
        core_json["pending_events"].as_a.should be_empty
        core_json["snapshot"]["version"].as_s.should eq "v1"

        # Verify pending updates are in separate file (JSONL format)
        updates_lines = File.read_lines(File.join(state_dir, "pending-updates.jsonl"))
        updates_lines.size.should eq 2
        updates_lines.each do |line|
          update = JSON.parse(line)
          update["action"].as_s.should eq "hset"
          update["hash_id"].as_s.should eq "status/mod-1"
        end

        # Verify pending events are in separate file (JSONL format)
        events_lines = File.read_lines(File.join(state_dir, "pending-events.jsonl"))
        events_lines.size.should eq 1
        event_json = JSON.parse(events_lines.first)
        event_json["event"]["kind"].as_s.should eq "module_started"
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
