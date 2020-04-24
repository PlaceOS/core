require "./application"
require "../core/module_manager"

module PlaceOS::Core::Api
  class Command < Application
    base "/api/core/v1/command/"

    def module_manager
      @module_manager || ModuleManager.instance
    end

    # Loads if not already loaded
    # If the module is already running, it will be updated to latest settings.
    post "/:module_id/load", :load do
      mod = Model::Module.find(params["module_id"])
      head :not_found if mod.nil?

      module_manager.load_module(mod)

      head :ok
    end

    # Executes a command against a module
    post "/:module_id/execute", :execute do
      module_id = params["module_id"]
      protocol_manager = module_manager.proc_manager_by_module?(module_id)

      unless protocol_manager
        Log.info { {module_id: module_id, message: "module not loaded"} }
        head :not_found
      end

      body = request.body
      unless body
        Log.info { "no request body" }
        head :not_acceptable
      end

      # We don't parse the request here or parse the response, just proxy it.
      exec_request = body.gets_to_end

      begin
        render json: protocol_manager.execute(module_id, exec_request)
      rescue error : PlaceOS::Driver::RemoteException
        Log.error(exception: error) { "execute errored" }
        render :non_authoritative_information, json: {
          message:   error.message,
          backtrace: error.backtrace?,
        }
      end
    end

    # For now a one-to-one debug session to websocket should be fine as it's not
    # a common operation and limited to system administrators
    ws "/:module_id/debugger", :module_debugger do |socket|
      module_id = params["module_id"]
      protocol_manager = module_manager.proc_manager_by_module?(module_id)
      raise "module not loaded" unless protocol_manager

      # Forward debug messages to the websocket
      callback = ->(message : String) { socket.send(message); nil }
      protocol_manager.debug(module_id, &callback)

      # Stop debugging when the socket closes
      socket.on_close { protocol_manager.as(Driver::Protocol::Management).ignore(module_id, &callback) }
    end

    # In the long term we should move to a single websocket between API instances
    # and core instances, then we multiplex the debugging signals accross.
    ws "/debugger", :debugger do |_socket|
      raise "not implemented"
    end

    # Overriding initializers for dependency injection
    ###########################################################################

    @module_manager : ModuleManager? = nil

    def initialize(@context, @action_name = :index, @__head_request__ = false)
      super(@context, @action_name, @__head_request__)
    end

    def initialize(
      context : HTTP::Server::Context,
      action_name = :index,
      @module_manager : ModuleManager = ModuleManager.instance
    )
      super(context, action_name)
    end
  end
end
