require "hardware"
require "hound-dog"

# For looking up binary directory
require "placeos-compiler/compiler"

require "../process_manager"
require "./common"

module PlaceOS::Core
  class ProcessManager::Local
    include ProcessManager
    include Common

    private getter discovery : HoundDog::Discovery

    def initialize(@discovery : HoundDog::Discovery)
    end

    def load(module_id : String, driver_key : String)
      driver_key = ProcessManager.path_to_key(driver_key)
      ::Log.with_context do
        Log.context.set(module_id: module_id, driver_key: driver_key)

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
      Log.error(exception: error) { {
        message:    "failed to load module",
        module_id:  module_id,
        driver_key: driver_key,
      } }
      false
    end

    private def driver_manager(driver_key : String)
      path = driver_path(driver_key).to_s
      Log.debug { {driver_path: path, message: "creating new driver protocol manager"} }
      Driver::Protocol::Management.new(path)
    end

    private def driver_path(driver_key : String) : Path
      Path.new(Compiler.binary_dir, ProcessManager.path_to_key(driver_key))
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
      # Protocol.instance.expect_response(@module_id, @reply_id, "exec", request, raw: true)
      remote_module_id = request.id
      raw_execute_json = request.payload.not_nil!

      core_uri = which_core(remote_module_id)

      # If module maps to this node
      if core_uri == discovery.uri
        if manager = protocol_manager_by_module?(remote_module_id)
          # responds with a JSON string
          request.payload = manager.execute(remote_module_id, raw_execute_json)
        else
          raise "could not locate module #{remote_module_id}. It may not be running."
        end
      else
        # build request
        core_uri.path = "/api/core/v1/command/#{remote_module_id}/execute"
        response = HTTP::Client.post(
          core_uri,
          headers: HTTP::Headers{"X-Request-ID" => "int-#{request.reply}-#{remote_module_id}-#{Time.utc.to_unix_ms}"},
          body: raw_execute_json
        )

        case response.status_code
        when 200
          # exec was successful, json string returned
          request.payload = response.body
        when 203
          # exec sent to module and it raised an error
          info = NamedTuple(message: String, backtrace: Array(String)?).from_json(response.body)
          request.payload = info[:message]
          request.backtrace = info[:backtrace]
          request.error = "RequestFailed"
        else
          # some other failure 3
          request.payload = "unexpected response code #{response.status_code}"
          request.error = "UnexpectedFailure"
        end
      end

      response_callback.call(request)
    rescue error
      request.set_error(error)
      response_callback.call(request)
    end

    # Clustering
    ###########################################################################

    # Used in `on_exec` for locating the remote module
    #
    def which_core(module_id : String) : URI
      node = discovery.find?(module_id)
      raise "no registered core instances" unless node
      node[:uri]
    end
  end
end
