require "../helper"

# Regression coverage for a hang that could block a node indefinitely.
#
# When a driver fails to compile, `DriverResource.load` returns an empty path, so
# the driver key degrades to `""` and the protocol manager ends up pointed at the
# *binaries directory* rather than a binary. `Common#start` guards against a
# missing binary specifically to avoid `Management#start_process` timing out
# internally without ever rejecting its promise — but the guard used
# `File.exists?`, which is true for a directory. The guard passed, the launch
# failed with `Permission denied`, and the manager relaunched forever.
module PlaceOS::Core::ProcessManager
  describe Local, tags: "processes" do
    it "fails fast rather than hanging when the driver path is not a binary" do
      pm = Local.new(discovery_mock)
      module_id = "missing-binary-#{UUID.random}"

      # An empty driver key is exactly what an uncompiled driver produces.
      pm.load(module_id: module_id, driver_key: "")

      # Run in a fiber so a regression surfaces as a failed spec rather than
      # wedging the whole suite (which is what the original bug did).
      outcome = Channel(String).new(1)
      spawn do
        begin
          pm.start(module_id: module_id, payload: "{}")
          outcome.send "started"
        rescue error
          outcome.send(error.message || "raised")
        end
      end

      select
      when message = outcome.receive
        message.should contain "Driver binary missing"
      when timeout 10.seconds
        raise "start blocked on a driver path that can never launch"
      end

      pm.unload(module_id) rescue nil
    end
  end
end
