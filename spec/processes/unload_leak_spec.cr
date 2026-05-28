require "../helper"

# Regression coverage for a fiber/heap leak in `ProcessManager::Common#unload`.
#
# A `Driver::Protocol::Management` spawns a long-lived `process_events` fiber in
# its constructor (i.e. as soon as a driver is `load`ed, before any process is
# launched). That fiber loops `until terminated?`, and the ONLY thing that flips
# `@terminated` is `Management#terminate`. If `unload` drops the manager from its
# maps without terminating it, the suspended `process_events` fiber keeps the
# whole manager object alive forever -> unbounded fiber + heap growth under the
# repeated load/unload churn produced by lazy modules.
#
# These specs deliberately use a dummy driver_key so they exercise the unload
# lifecycle without depending on a compiled driver binary (the leaked fiber is
# created in the manager constructor, no child process required).
module PlaceOS::Core::ProcessManager
  count_process_events_fibers = -> {
    count = 0
    Fiber.each { |fiber| count += 1 if fiber.name == "process_events" }
    count
  }

  describe Local, tags: "processes" do
    it "terminates the driver manager when the last module is unloaded" do
      pm = Local.new(discovery_mock)
      driver_key = "leak-test-#{UUID.random}"
      module_id = "leak-mod"

      pm.load(module_id: module_id, driver_key: driver_key)
      manager = pm.protocol_manager_by_driver?(driver_key).not_nil!
      manager.terminated?.should be_false

      pm.unload(module_id)

      # allow the :terminate event to be processed by process_events
      sleep 200.milliseconds
      manager.terminated?.should be_true
    end

    it "does not leak process_events fibers across repeated load/unload cycles" do
      pm = Local.new(discovery_mock)
      before = count_process_events_fibers.call

      5.times do |i|
        driver_key = "leak-cycle-#{UUID.random}"
        module_id = "cycle-mod-#{i}"

        pm.load(module_id: module_id, driver_key: driver_key)
        pm.unload(module_id)
        sleep 100.milliseconds
      end

      # give any pending terminations time to unwind their fibers
      sleep 200.milliseconds

      (count_process_events_fibers.call - before).should eq 0
    end
  end
end
