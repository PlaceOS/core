require "./helper"
require "../processes/support"
require "file_utils"

module PlaceOS::Edge
  describe Reconciler, tags: ["edge"] do
    it "loads and starts modules from the desired snapshot diff" do
      PlaceOS::Core::ProcessManager.with_driver do |mod, _driver_path, driver_key, _driver|
        dir = File.join(Dir.tempdir, "edge-reconciler-#{UUID.random}")
        begin
          Dir.mkdir_p(dir)
          store = RuntimeStore.new(dir)
          runtime = RuntimeManager.new
          binary = BinaryManager.new("edge-123", PLACE_URI, CLIENT_SECRET)
          reconciler = Reconciler.new(store, binary, runtime)

          snapshot = State::Snapshot.new(
            edge_id: "edge-123",
            version: "v1",
            last_modified: Time.utc,
            drivers: [State::DesiredDriver.new(driver_key)],
            modules: [State::DesiredModule.new(
              mod.id.as(String),
              driver_key,
              true,
              PlaceOS::Core::ModuleManager.start_payload(mod)
            )]
          )

          reconciler.apply(snapshot)

          runtime.driver_loaded?(driver_key).should be_true
          runtime.module_loaded?(mod.id.as(String)).should be_true
          runtime_store_module = store.runtime_modules[mod.id.as(String)]
          runtime_store_module.loaded.should be_true
          runtime_store_module.running.should be_true
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end

    it "stops and unloads modules removed from the desired snapshot" do
      PlaceOS::Core::ProcessManager.with_driver do |mod, _driver_path, driver_key, _driver|
        dir = File.join(Dir.tempdir, "edge-reconciler-#{UUID.random}")
        begin
          Dir.mkdir_p(dir)
          store = RuntimeStore.new(dir)
          runtime = RuntimeManager.new
          binary = BinaryManager.new("edge-123", PLACE_URI, CLIENT_SECRET)
          reconciler = Reconciler.new(store, binary, runtime)

          initial = State::Snapshot.new(
            edge_id: "edge-123",
            version: "v1",
            last_modified: Time.utc,
            drivers: [State::DesiredDriver.new(driver_key)],
            modules: [State::DesiredModule.new(
              mod.id.as(String),
              driver_key,
              true,
              PlaceOS::Core::ModuleManager.start_payload(mod)
            )]
          )
          reconciler.apply(initial)

          removed = State::Snapshot.new(
            edge_id: "edge-123",
            version: "v2",
            last_modified: Time.utc + 1.second,
            drivers: [] of State::DesiredDriver,
            modules: [] of State::DesiredModule
          )
          reconciler.apply(removed)

          runtime.module_loaded?(mod.id.as(String)).should be_false
          store.runtime_modules.has_key?(mod.id.as(String)).should be_false
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end

    it "restarts a running module when the desired payload changes" do
      PlaceOS::Core::ProcessManager.with_driver do |mod, _driver_path, driver_key, _driver|
        dir = File.join(Dir.tempdir, "edge-reconciler-#{UUID.random}")
        begin
          Dir.mkdir_p(dir)
          store = RuntimeStore.new(dir)
          runtime = RuntimeManager.new
          binary = BinaryManager.new("edge-123", PLACE_URI, CLIENT_SECRET)
          events = [] of State::RuntimeEvent
          reconciler = Reconciler.new(store, binary, runtime, ->(event : State::RuntimeEvent) { events << event })

          initial_payload = PlaceOS::Core::ModuleManager.start_payload(mod)
          initial = State::Snapshot.new(
            edge_id: "edge-123",
            version: "v1",
            last_modified: Time.utc,
            drivers: [State::DesiredDriver.new(driver_key)],
            modules: [State::DesiredModule.new(mod.id.as(String), driver_key, true, initial_payload)]
          )
          reconciler.apply(initial)

          payload_hash = Hash(String, JSON::Any).from_json(initial_payload)
          payload_hash["custom_name"] = JSON::Any.new("payload-updated")
          updated_payload = payload_hash.to_json
          updated = State::Snapshot.new(
            edge_id: "edge-123",
            version: "v2",
            last_modified: Time.utc + 1.second,
            drivers: [State::DesiredDriver.new(driver_key)],
            modules: [State::DesiredModule.new(mod.id.as(String), driver_key, true, updated_payload)]
          )
          reconciler.apply(updated)

          runtime_store_module = store.runtime_modules[mod.id.as(String)]
          runtime_store_module.running.should be_true
          runtime_store_module.payload.should eq updated_payload

          events.any? { |event| event.kind.module_stopped? && event.message == "payload changed" }.should be_true
          (events.count(&.kind.module_started?) > 1).should be_true
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end
  end
end
