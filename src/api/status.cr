require "hardware"

require "../placeos-core/resources"
require "../placeos-core/resources/modules"
require "../placeos-core/process_manager"
require "./application"

module PlaceOS::Core::Api
  class Status < Application
    base "/api/core/v1/status/"

    # Callbacks
    ###############################################################################################

    before_action :current_driver, only: [:driver]

    ###############################################################################################

    getter driver_id : String { route_params["driver_id"] }

    # Returns 404 if the document is not found.
    getter current_driver : Model::Driver do
      Log.context.set(driver_id: driver_id)
      Model::Driver.find!(driver_id, runopts: {"read_mode" => "majority"})
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

    # /api/core/v1/status/driver/:id
    get "/driver/:id", :driver do
      executable = begin
        Model::Executable.new(Core::ProcessManager.driver_name(current_driver.file_name))
      rescue error : Model::Error
        Log.info(exception: error) { "failed to parse #{driver_name} as a well-formed executable" }
        nil
      end

      if executable.nil?
        head :unprocessable_entity
      else
        render json: {
          local: module_manager.local_processes.driver_status(executable.filename, driver_id),
          edge:  module_manager.edge_processes.driver_status(executable.filename, driver_id),
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
