require "../helper"
require "../support/stub_driver_store"

# Regression coverage for "Driver not compiled for lazy module".
#
# A `launch_on_execute` module spawns its driver at execute time, long after the
# module was registered. By then the binary may be gone locally (the cleanup job
# deletes binaries that haven't run for weeks — rarely-used lazy drivers are
# exactly the ones it reaches) and the build service may no longer hold an
# artifact for that commit. The lazy path used to only *ask* whether an artifact
# existed, so once the answer was "no" every execute failed identically until the
# service was restarted. It must fall back to requesting a build, the way startup
# and the integrity checker always have.
module PlaceOS::Core::ProcessManager
  describe Local, tags: "processes" do
    describe "lazy module driver fetch" do
      lazy_module = ->(driver : PlaceOS::Model::Driver) {
        mod = PlaceOS::Model::Generator.module(driver: driver)
        mod.launch_on_execute = true
        mod.running = true
        mod.save!
        mod
      }

      it "requests a build when the driver has no prebuilt artifact" do
        _, driver, _ = setup(role: PlaceOS::Model::Driver::Role::Service)
        mod = lazy_module.call(driver)

        store = Core.stub_store
        store.download_available = false
        store.build_succeeds = false

        pm = Local.new(discovery_mock, store)

        expect_raises(ModuleError, /could not supply or build/) do
          pm.execute(
            module_id: mod.id.as(String),
            payload: ModuleManager.execute_payload(:used_for_place_testing),
            user_id: nil,
          )
        end

        # The point of the fix: the lazy path escalated from "is it built?" to
        # "please build it" instead of giving up.
        store.download_calls.should eq 1
        store.build_calls.should eq 1
      end

      it "does not leave a lazy module wedged after a failed fetch" do
        _, driver, _ = setup(role: PlaceOS::Model::Driver::Role::Service)
        mod = lazy_module.call(driver)
        module_id = mod.id.as(String)

        store = Core.stub_store
        store.download_available = false
        store.build_succeeds = false

        pm = Local.new(discovery_mock, store)
        payload = ModuleManager.execute_payload(:used_for_place_testing)

        expect_raises(ModuleError) { pm.execute(module_id: module_id, payload: payload, user_id: nil) }

        # A second execute must try again rather than replay the first failure.
        expect_raises(ModuleError) { pm.execute(module_id: module_id, payload: payload, user_id: nil) }

        store.download_calls.should eq 2
        store.build_calls.should eq 2

        # Nothing half-loaded should have been left behind for the module.
        pm.module_loaded?(module_id).should be_false
      end
    end
  end
end
