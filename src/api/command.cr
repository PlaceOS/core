require "./application"
require "../placeos-core/module_manager"

module PlaceOS::Core::Api
  class Command < Application
    base "/api/core/v1/command/"

    property module_manager : ModuleManager { ModuleManager.instance }

    # Loads if not already loaded
    # If the module is already running, it will be updated to latest settings.
    @[AC::Route::POST("/:module_id/load")]
    def load(
      @[AC::Param::Info(description: "the module id we want to load", example: "mod-1234")]
      module_id : String,
    ) : Nil
      mod = Model::Module.find(module_id)
      raise Error::NotFound.new("module #{module_id} not found in database") unless mod
      module_manager.load_module(mod)
    end

    # Executes a command against a module
    @[AC::Route::POST("/:module_id/execute")]
    def execute(
      @[AC::Param::Info(description: "the module id we want to send an execute request to", example: "mod-1234")]
      module_id : String,
      @[AC::Param::Info(description: "the user context for the execution", example: "user-1234")]
      user_id : String? = nil,
    ) : Nil
      manager, mod_orm = module_manager.process_manager(module_id)

      # NOTE:: we don't use the AC body helper for performance reasons.
      # we're just proxying the JSON to the driver without parsing it
      body = request.body.try &.gets_to_end
      if body.nil?
        message = "no request body provided"
        Log.info { message }
        raise Error::NotAcceptable.new(message)
      end

      execute_output = manager.execute(module_id, body, user_id: user_id, mod: mod_orm)

      # NOTE:: we are not using the typical response processing
      # as we don't need to deserialise
      response.content_type = "application/json"
      if execute_output
        response.headers[RESPONSE_CODE_HEADER] = execute_output[1].to_s
        render text: execute_output[0]
      else
        render text: ""
      end
    end

    # For now a one-to-one debug session to websocket should be fine as it's not
    # a common operation and limited to system administrators
    @[AC::Route::WebSocket("/:module_id/debugger")]
    def module_debugger(
      socket,
      @[AC::Param::Info(description: "the module we want to debug", example: "mod-1234")]
      module_id : String,
    ) : Nil
      # Forward debug messages to the websocket
      manager, _mod_orm = module_manager.process_manager(module_id)
      manager.attach_debugger(module_id, socket)
    end

    @[AC::Route::Exception(PlaceOS::Driver::RemoteException, status_code: HTTP::Status::NON_AUTHORITATIVE_INFORMATION)]
    def remote_exception(error) : CommonError
      Log.error(exception: error) { "execute errored" }
      CommonError.new(error)
    end
  end
end
