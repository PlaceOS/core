require "./application"
require "../placeos-core/module_manager"

module PlaceOS::Core::Api
  class Command < Application
    base "/api/core/v1/command/"

    getter module_manager : ModuleManager { ModuleManager.instance }

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
      user_id = params["user_id"]?.presence

      unless module_manager.process_manager(module_id, &.module_loaded?(module_id))
        Log.info { {module_id: module_id, message: "module not loaded"} }
        head :not_found
      end

      body = request.body.try &.gets_to_end
      if body.nil?
        Log.info { "no request body" }
        head :not_acceptable
      end

      begin
        execute_output = module_manager.process_manager(module_id) do |manager|
          manager.execute(module_id, body, user_id: user_id)
        end

        response.content_type = "application/json"
        if execute_output
          response.headers[RESPONSE_CODE_HEADER] = execute_output[1].to_s
          render text: execute_output[0]
        else
          render text: ""
        end
      rescue error : PlaceOS::Driver::RemoteException
        Log.error(exception: error) { "execute errored" }
        response.headers[RESPONSE_CODE_HEADER] = error.code.to_s
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

      Log.trace { {message: "binding debug session to module", module_id: module_id} }

      # Forward debug messages to the websocket
      module_manager.process_manager(module_id) do |manager|
        debug_lock = Mutex.new
        callback = ->(message : String) { debug_lock.synchronize { socket.send(message) }; nil }
        manager.debug(module_id, &callback)
        # Stop debugging when the socket closes
        socket.on_close { stop_debugging(module_id, callback) }
      end
    end

    # Stop debugging against the current module manager for `module_id`
    protected def stop_debugging(module_id, callback)
      module_manager.process_manager(module_id) do |manager|
        manager.ignore(module_id, &callback)
      end
    end

    # Overriding initializers for dependency injection
    ###########################################################################

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
