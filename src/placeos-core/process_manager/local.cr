require "hardware"
require "redis_service_manager"

require "../process_manager"
require "./common"

module PlaceOS::Core
  class ProcessManager::Local
    include ProcessManager
    include Common

    private getter discovery : Clustering::Discovery
    private getter store : DriverStore

    # Track active execute requests for lazy modules (module_id => count)
    private getter lazy_execute_counts : Hash(String, Atomic(Int32)) = {} of String => Atomic(Int32)
    private getter lazy_execute_lock : Mutex = Mutex.new

    # Track scheduled unload fibers to cancel them if new executions come in
    private getter lazy_unload_scheduled : Hash(String, Bool) = {} of String => Bool

    def initialize(@discovery : Clustering::Discovery)
      @store = DriverStore.new
    end

    def load(module_id : String, driver_key : String)
      driver_key = ProcessManager.path_to_key(driver_key)
      ::Log.with_context(module_id: module_id, driver_key: driver_key) do
        if protocol_manager_by_module?(module_id)
          Log.info { "module already loaded" }
          return true
        end

        if existing_driver_manager = protocol_manager_by_driver?(driver_key)
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
      # Check if this is a lazy module that needs to be loaded
      mod = Model::Module.find?(module_id)
      if mod && mod.launch_on_execute
        return execute_lazy(mod, payload, user_id)
      end

      super
    rescue exception : ModuleError
      if exception.message =~ /module #{module_id} not running on this host/
        raise no_module_error(module_id, exception)
      else
        raise exception
      end
    end

    # Execute on a lazy-load module: spawn driver if needed, execute, schedule unload
    private def execute_lazy(mod : Model::Module, payload : String | IO, user_id : String?)
      module_id = mod.id.as(String)

      # Track this execution
      increment_lazy_execute_count(module_id)

      begin
        # Ensure driver is spawned and module is loaded
        ensure_lazy_module_loaded(mod)

        # Execute the request
        manager = protocol_manager_by_module?(module_id)
        raise ModuleError.new("No protocol manager for lazy module #{module_id}") if manager.nil?

        request_body = payload.is_a?(IO) ? payload.gets_to_end : payload
        manager.execute(module_id, request_body, user_id: user_id)
      ensure
        # Decrement and potentially schedule unload
        remaining = decrement_lazy_execute_count(module_id)
        schedule_lazy_unload(mod) if remaining == 0
      end
    end

    # Spawn driver and load module for lazy execution
    private def ensure_lazy_module_loaded(mod : Model::Module)
      module_id = mod.id.as(String)

      # Already loaded?
      if protocol_manager_by_module?(module_id)
        Log.debug { {message: "lazy module already loaded", module_id: module_id} }
        return
      end

      driver = mod.driver!
      repository = driver.repository!

      driver_path = store.built?(driver.file_name, driver.commit, repository.branch, repository.uri)
      raise ModuleError.new("Driver not compiled for lazy module #{module_id}") if driver_path.nil?

      ::Log.with_context(module_id: module_id, driver_key: driver_path) do
        # Spawn driver and register module
        load(module_id, driver_path.to_s)

        # Start the module instance
        manager = protocol_manager_by_module?(module_id)
        raise ModuleError.new("Failed to load lazy module #{module_id}") if manager.nil?

        manager.start(module_id, ModuleManager.start_payload(mod))

        Log.info { {message: "spawned driver for lazy module execution", module_id: module_id, name: mod.name} }
      end
    end

    # Schedule unload of lazy module after idle timeout
    private def schedule_lazy_unload(mod : Model::Module)
      module_id = mod.id.as(String)

      lazy_execute_lock.synchronize do
        # Mark that unload is scheduled
        lazy_unload_scheduled[module_id] = true
      end

      spawn do
        sleep ModuleManager.lazy_unload_delay

        # Check if still no active executions and unload still scheduled
        should_unload = lazy_execute_lock.synchronize do
          scheduled = lazy_unload_scheduled.delete(module_id)
          count = lazy_execute_counts[module_id]?.try(&.get) || 0
          scheduled && count == 0
        end

        if should_unload
          unload_lazy_module(mod)
        end
      end
    end

    # Unload a lazy module after idle timeout
    private def unload_lazy_module(mod : Model::Module)
      module_id = mod.id.as(String)

      # Double-check no active executions
      count = lazy_execute_lock.synchronize do
        lazy_execute_counts[module_id]?.try(&.get) || 0
      end

      if count > 0
        Log.debug { {message: "skipping lazy unload, active executions", module_id: module_id, count: count} }
        return
      end

      # Stop and unload the module
      stop(module_id)
      unload(module_id)

      Log.info { {message: "unloaded lazy module after idle timeout", module_id: module_id, name: mod.name} }
    end

    # Increment active execution count for a lazy module
    private def increment_lazy_execute_count(module_id : String)
      lazy_execute_lock.synchronize do
        lazy_execute_counts[module_id] ||= Atomic(Int32).new(0)
        lazy_execute_counts[module_id].add(1)

        # Cancel any scheduled unload
        lazy_unload_scheduled.delete(module_id)
      end
    end

    # Decrement active execution count, returns remaining count
    private def decrement_lazy_execute_count(module_id : String) : Int32
      lazy_execute_lock.synchronize do
        counter = lazy_execute_counts[module_id]?
        return 0 unless counter
        new_count = counter.sub(1)
        # Clean up if zero
        lazy_execute_counts.delete(module_id) if new_count == 0
        new_count
      end
    end

    # Check if a lazy module has active executions
    def lazy_module_active?(module_id : String) : Bool
      lazy_execute_lock.synchronize do
        counter = lazy_execute_counts[module_id]?
        counter ? counter.get > 0 : false
      end
    end

    private def driver_manager(driver_key : String)
      path = driver_path(driver_key).to_s
      Log.info { {driver_path: path, message: "creating new driver protocol manager"} }

      Driver::Protocol::Management.new(path).tap do
        unless File.exists?(path)
          Log.warn { {driver_path: path, message: "driver manager created for a driver that is not compiled"} }
        end
      end
    end

    private def driver_path(driver_key : String) : Path
      store.path(ProcessManager.path_to_key(driver_key))
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
      module_manager = ModuleManager.instance
      module_id = request.id
      request = if module_manager.process_manager(module_id, &.module_loaded?(module_id))
                  local_execute(request)
                else
                  core_uri = which_core(module_id)
                  if core_uri == discovery.uri
                    # If the module maps to this node
                    local_execute(request)
                  else
                    # Otherwise, dial core node responsible for the module
                    remote_execute(core_uri, request)
                  end
                end
      response_callback.call(request)
    rescue error
      request.set_error(error)
      response_callback.call(request)
    end

    protected def remote_execute(core_uri, request)
      remote_module_id = request.id

      # Build remote core request
      user_id = request.user_id
      params = user_id ? "?user_id=#{user_id}" : nil
      core_uri.path = "/api/core/v1/command/#{remote_module_id}/execute#{params}"
      response = HTTP::Client.post(
        core_uri,
        headers: HTTP::Headers{"X-Request-ID" => "int-#{request.reply}-#{remote_module_id}-#{Time.utc.to_unix_ms}"},
        body: request.payload.as(String),
      )

      request.code = response.headers[RESPONSE_CODE_HEADER]?.try(&.to_i) || 500

      case response.status_code
      when 200
        # exec was successful, json string returned
        request.payload = response.body
      when 203
        # exec sent to module and it raised an error
        info = NamedTuple(message: String?, backtrace: Array(String)?, code: Int32?).from_json(response.body)
        request.payload = info[:message] || "request failed"
        request.backtrace = info[:backtrace]
        request.code = info[:code] || 500
        request.error = "RequestFailed"
      else
        # some other failure 3
        request.payload = "unexpected response code #{response.status_code}"
        request.error = "UnexpectedFailure"
        request.code ||= 500
      end

      request.cmd = :result
      request
    end

    protected def local_execute(request)
      module_id = request.id

      module_manager = ModuleManager.instance
      unless module_manager.process_manager(module_id, &.module_loaded?(module_id))
        Log.info { {module_id: module_id, message: "module not loaded"} }
        # Attempt to start the module, recover from abnormal conditions
        begin
          module_manager.start_module(Model::Module.find!(module_id))
        rescue exception
          raise no_module_error(module_id, exception)
        end
        raise no_module_error(module_id) unless module_manager.process_manager(module_id, &.module_loaded?(module_id))
      end

      begin
        response = module_manager.process_manager(module_id) { |manager|
          manager.execute(module_id, request.payload.as(String), user_id: request.user_id)
        } || {"".as(String?), 500}
        request.code = response[1]
        request.payload = response[0]
      rescue exception
        if exception.message.try(&.includes?("module #{module_id} not running on this host"))
          raise no_module_error(module_id, exception)
        else
          raise exception
        end
      end

      request.cmd = :result
      request
    end

    # Render more information for missing module exceptions
    #
    protected def no_module_error(module_id, cause : Exception? = nil)
      reason = if remote_module = Model::Module.find(module_id)
                 if remote_module.running
                   "it is running but not loaded. Check driver is compiled."
                 else
                   "it is stopped"
                 end
               else
                 "it is not present in the database"
               end

      ModuleError.new("Could not locate module #{module_id}, #{reason}", cause: cause)
    end

    # Clustering
    ###########################################################################

    # Used in `on_exec` for locating the remote module
    #
    def which_core(module_id : String) : URI
      edge_id = Model::Module.find!(module_id).edge_id if Model::Module.has_edge_hint?(module_id)
      node = edge_id ? discovery.find?(edge_id) : discovery.find?(module_id)
      raise Error.new("No registered core instances") if node.nil?
      node
    end
  end
end
