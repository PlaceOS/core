require "./application"

require "../engine-core/module_manager"

module ACAEngine::Core::Api
  class Chaos < Application
    base "/api/core/v1/chaos/"

    def module_manager
      @module_manager || ModuleManager.instance
    end

    # terminate a process
    post "/terminate", :terminate do
      driver = params["path"]
      protocol_manager = module_manager.manager_by_driver_path(driver)
      head :not_found unless protocol_manager
      head :ok unless protocol_manager.running?

      pid = protocol_manager.pid
      Process.run("kill", {"-9", pid.to_s})

      head :ok
    end

    # Overriding initializers for dependency injection
    ###########################################################################

    @module_manager : ModuleManager? = nil

    def initialize(@context, @action_name = :index, @__head_request__ = false)
      super(@context, @action_name, @__head_request__)
    end

    # Override initializer for specs
    def initialize(
      context : HTTP::Server::Context,
      action_name = :index,
      @module_manager : ModuleManager = ModuleManager.instance
    )
      super(context, action_name)
    end
  end
end
