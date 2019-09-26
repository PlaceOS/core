require "./application"

module Engine::Core
  class Chaos < Application
    base "/api/core/v1/chaos/"

    # TODO:: lookup the driver manager in a global dispatch
    # This needs to exist somewhere
    DriverExecLookup = {} of String => EngineDriver::Protocol::Management

    # terminate a process
    post "/terminate" do
      driver = params["path"]
      manager = DriverExecLookup[driver]?
      head :not_found unless manager
      head :ok unless manager.running?

      pid = manager.pid
      Process.run("kill", {"-9", pid.to_s})

      head :ok
    end
  end
end
