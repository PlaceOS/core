require "hardware"
require "hound-dog"

require "../process_manager"
require "./common"

module PlaceOS::Core
  class ProcessManager::Local
    include ProcessManager
    include Common

    private getter discovery : HoundDog::Discovery

    def initialize(@discovery : HoundDog::Discovery, @binary_store : Build::Filesystem)
    end

    def load(module_id : String, driver_key : String)
      driver_key = ProcessManager.path_to_key(driver_key)
      ::Log.with_context(module_id: module_id, driver_key: driver_key) do
        if protocol_manager_by_module?(module_id)
          Log.info { "module already loaded" }
          return true
        end

        if (existing_driver_manager = protocol_manager_by_driver?(driver_key))
          Log.debug { "using existing protocol manager" }
          set_module_protocol_manager(module_id, existing_driver_manager)
        else
          manager = driver_manager(driver_key)

          # Hook up the callbacks
          manager.on_exec = ->on_exec(Request, (Request ->))
          manager.on_system_model = ->on_system_model(Request, (Request ->))
          manager.on_setting = ->on_setting(String, String, YAML::Any)

          set_module_protocol_manager(module_id, manager)
          set_driver_protocol_manager(driver_key, manager)
        end

        Log.info { "loaded module" }
        true
      end
    rescue error
      # Wrap exception with additional context
      error = module_error(module_id, error)
      Log.error(exception: error) { {
        message:    "failed to load module",
        module_id:  module_id,
        driver_key: driver_key,
      } }
      false
    end

    def execute(module_id : String, payload : String | IO, user_id : String?)
      super
    rescue exception : ModuleError
      if exception.message =~ /module #{module_id} not running on this host/
        raise no_module_error(module_id)
      else
        raise exception
      end
    end

    private def driver_manager(driver_key : String)
      path = driver_path(driver_key)
      Log.info { {driver_path: path, message: "creating new driver protocol manager"} }

      Driver::Protocol::Management.new(path).tap do
        unless File.exists?(path)
          Log.warn { {driver_path: path, message: "driver manager created for a driver that is not compiled"} }
        end
      end
    end

    private def driver_path(driver_key : String) : String
      key = ProcessManager.path_to_key(driver_key)
      binary_store.path(Model::Executable.new(key))
    end

    # Callbacks
    ###############################################################################################

    def on_system_model(request : Request, response_callback : Request ->)
      request.payload = PlaceOS::Model::ControlSystem.find!(request.id).to_json
    rescue error
      request.set_error(error)
    ensure
      response_callback.call(request)
    end

    def on_exec(request : Request, response_callback : Request ->)
      core_uri = which_core(request.id)

      request = if core_uri == discovery.uri
                  # If the module maps to this node
                  local_execute(request)
                else
                  # Otherwise, dial core node responsible for the module
                  remote_execute(core_uri, request)
                end

      response_callback.call(request)
    rescue error
      request.set_error(error)
      response_callback.call(request)
    end

    protected def remote_execute(core_uri, request)
      remote_module_id = request.id

      # Build remote core request
      # TODO: Use `PlaceOS/core-client` for forwarding execute requests
      core_uri.path = "/api/core/v1/command/#{remote_module_id}/execute"
      response = HTTP::Client.post(
        core_uri,
        headers: HTTP::Headers{"X-Request-ID" => "int-#{request.reply}-#{remote_module_id}-#{Time.utc.to_unix_ms}"},
        body: request.payload.not_nil!,
      )

      request.code = response.headers[RESPONSE_CODE_HEADER]?.try(&.to_i) || 500

      case response.status_code
      when 200
        # exec was successful, json string returned
        request.payload = response.body
      when 203
        # exec sent to module and it raised an error
        info = NamedTuple(message: String, backtrace: Array(String)?, code: Int32?).from_json(response.body)
        request.payload = info[:message]
        request.backtrace = info[:backtrace]
        request.code = info[:code] || 500
        request.error = "RequestFailed"
      else
        # some other failure 3
        request.payload = "unexpected response code #{response.status_code}"
        request.error = "UnexpectedFailure"
        request.code ||= 500
      end

      request
    end

    protected def local_execute(request)
      remote_module_id = request.id

      if manager = protocol_manager_by_module?(remote_module_id)
        begin
          # responds with a JSON string
          response = manager.execute(remote_module_id, request.payload.not_nil!)
          request.code = response[1]
          request.payload = response[0]
        rescue exception
          if exception.message.try(&.includes?("module #{remote_module_id} not running on this host"))
            raise no_module_error(remote_module_id)
          else
            raise exception
          end
        end
      else
        raise no_module_error(remote_module_id)
      end

      request
    end

    # Render more information for missing module exceptions
    #
    protected def no_module_error(module_id)
      reason = if remote_module = Model::Module.find(module_id)
                 if remote_module.running
                   "it is running but not loaded on this host"
                 else
                   "it is stopped"
                 end
               else
                 "it is not present in the database"
               end

      ModuleError.new("Could not locate module #{module_id}, #{reason}")
    end

    # Clustering
    ###########################################################################

    # Used in `on_exec` for locating the remote module
    #
    def which_core(module_id : String) : URI
      node = discovery.find?(module_id)
      raise Error.new("No registered core instances") if node.nil?
      node[:uri]
    end
  end
end
