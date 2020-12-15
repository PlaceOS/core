require "hardware"
require "placeos-compiler/helper"

require "../placeos-core/module_manager"
require "../placeos-core/resource_manager"
require "./application"

module PlaceOS::Core::Api
  class Status < Application
    base "/api/core/v1/status/"
    id_param :commit_hash

    getter module_manager : ModuleManager { ModuleManager.instance }
    getter resource_manager : ResourceManager { ResourceManager.instance }

    # General statistics related to the process
    def index
      render json: {
        available_repositories:   PlaceOS::Compiler::Helper.repositories,
        unavailable_repositories: resource_manager.cloning.errors,
        compiled_drivers:         PlaceOS::Compiler::Helper.compiled_drivers,
        unavailable_drivers:      resource_manager.compilation.errors,
        run_count:                {
          local: module_manager.local_processes.run_count,
          edge:  module_manager.edge_processes.run_count,
        },
      }
    end

    # details related to a process (+ anything else we can think of)
    # /api/core/v1/status/driver?path=/path/to/compiled_driver
    get "/driver", :driver do
      driver_path = params["path"]?
      head :unprocessable_entity unless driver_path

      render json: {
        local: module_manager.local_processes.driver_status(driver_path),
        edge:  module_manager.edge_processes.driver_status(driver_path),
      }
    end

    # details about the overall machine load
    get "/load", :load do
      render json: {
        local: module_manager.local_processes.system_status,
        edge:  module_manager.edge_processes.system_status,
      }
    end

    # Returns the lists of modules drivers have loaded for this core, and managed edges
    get "/loaded", :loaded do
      render json: {
        local: module_manager.local_processes.loaded_modules,
        edge:  module_manager.edge_processes.loaded_modules,
      }
    end

    # Overriding initializers for dependency injection
    ###########################################################################

    def initialize(@context, @action_name = :index, @__head_request__ = false)
      super(@context, @action_name, @__head_request__)
    end

    def initialize(
      context : HTTP::Server::Context,
      action_name = :index,
      @module_manager : ModuleManager = ModuleManager.instance,
      @resource_manager : ResourceManager = ResourceManager.instance
    )
      super(context, action_name)
    end
  end
end
