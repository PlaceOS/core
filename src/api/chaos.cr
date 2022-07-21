require "./application"

require "../placeos-core/resources/modules"

module PlaceOS::Core::Api
  class Chaos < Application
    base "/api/core/v1/chaos/"

    getter module_manager : Resources::Modules { Resources::Modules.instance }

    # Terminate a process by executable path
    post "/terminate", :terminate do
      # TODO: Add option to kill via driver_id
      # driver_key = params["path"]?.presence
      # driver_id = params["driver_id"]?.presence
      driver_key = params["path"]
      edge_id = params["edge_id"]?.presence

      head :not_found unless manager = module_manager.process_manager(driver_key, edge_id)

      manager.kill(driver_key)

      head :ok
    end

    # Overriding initializers for dependency injection
    ###########################################################################

    def initialize(@context, @action_name = :index, @__head_request__ = false)
      super(@context, @action_name, @__head_request__)
    end

    # Override initializer for specs
    def initialize(
      context : HTTP::Server::Context,
      action_name = :index,
      @module_manager : Resources::Modules = Resources::Modules.instance
    )
      super(context, action_name)
    end
  end
end
