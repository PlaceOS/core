require "./application"
require "../engine-core"

module ACAEngine::Core
  class Chaos < Application
    base "/api/core/v1/chaos/"

    @manager = ModuleManager.instance

    # terminate a process
    post "/terminate" do
      driver = params["path"]
      manager = @manager.manager_by_driver_path(driver)
      head :not_found unless manager
      head :ok unless manager.running?

      pid = manager.pid
      Process.run("kill", {"-9", pid.to_s})

      head :ok
    end
  end
end
