require "./application"

require "../placeos-core/resources/modules"

module PlaceOS::Core::Api
  class Chaos < Application
    base "/api/core/v1/chaos/"

    getter module_manager : Resources::Modules { Resources::Modules.instance }

    # terminate a process
    post "/terminate", :terminate do
      driver_key = params["path"]
      edge_id = params["edge_id"]?.presence

      # TODO: move this to ModuleManager
      manager = if edge_id.nil? || !module_manager.own_node?(edge_id)
                  module_manager.local_processes
                else
                  module_manager.edge_processes.for?(edge_id)
                end

      head :not_found unless manager && manager.driver_loaded?(driver_key)

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
