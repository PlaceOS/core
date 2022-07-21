require "hardware"

require "../placeos-core/resources"
require "../placeos-core/resources/modules"
require "../placeos-core/process_manager"
require "./application"

module PlaceOS::Core::Api
  class Status < Application
    base "/api/core/v1/status/"

    # TODO: Enable this when lookup is implemented with respect to the driver_id
    # before_action :current_driver, only: [:driver]

    ###############################################################################################

    getter current_driver : Model::Driver do
      id = params["id"]
      Log.context.set(driver_id: id)
      # Find will raise a 404 (not found) if there is an error
      Model::Driver.find!(id, runopts: {"read_mode" => "majority"})
    end

    ###############################################################################################

    getter module_manager : Resources::Modules { Resources::Modules.instance }
    getter resource_manager : Resources::Manager { Resources::Manager.instance }

    # General statistics related to the process
    #
    def index
      render json: {
        driver_binaries: module_manager.binary_store.query,
        run_count:       {
          local: module_manager.local_processes.run_count,
          edge:  module_manager.edge_processes.run_count,
        },
      }
    end

    # Details related to a process (+ anything else we can think of)
    #
    # /api/core/v1/status/driver/:path
    get "/driver/:path", :driver do
      key = Core::ProcessManager.path_to_key(route_params["path"])

      executable = begin
        Model::Executable.new(key)
      rescue error : Model::Error
        Log.info(exception: error) { "failed to parse #{key} as a well-formed executable" }
        nil
      end

      if executable.nil?
        head :unprocessable_entity
      else
        key = executable.filename
        render json: {
          local: module_manager.local_processes.driver_status(key),
          edge:  module_manager.edge_processes.driver_status(key),
        }
      end
    end

    # Details about the overall machine load
    #
    get "/load", :load do
      render json: {
        local: module_manager.local_processes.system_status,
        edge:  module_manager.edge_processes.system_status,
      }
    end

    # Returns the lists of modules drivers have loaded for this core, and managed edges
    #
    get "/modules", :loaded do
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
      @module_manager : Resources::Modules = Resources::Modules.instance,
      @resource_manager : Resources::Manager = Resources::Manager.instance
    )
      super(context, action_name)
    end
  end
end
