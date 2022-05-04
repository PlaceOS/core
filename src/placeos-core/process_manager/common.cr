require "hardware"
require "placeos-compiler/compiler"

# Methods for interacting with module processes common across a local and edge node
module PlaceOS::Core::ProcessManager::Common
  def execute(module_id : String, payload : String | IO, user_id : String?)
    manager = protocol_manager_by_module?(module_id)

    raise ModuleError.new("No protocol manager for #{module_id}") if manager.nil?

    request_body = payload.is_a?(IO) ? payload.gets_to_end : payload
    manager.execute(
      module_id,
      request_body,
      user_id: user_id,
    )
  rescue error : PlaceOS::Driver::RemoteException
    raise error
  rescue exception
    raise module_error(module_id, exception)
  end

  def start(module_id : String, payload : String)
    manager = protocol_manager_by_module?(module_id)

    raise ModuleError.new("No protocol manager for #{module_id}") if manager.nil?

    manager.start(module_id, payload)
  rescue exception
    raise module_error(module_id, exception)
  end

  def stop(module_id : String)
    !!protocol_manager_by_module?(module_id).try(&.stop(module_id))
  rescue exception
    raise module_error(module_id, exception)
  end

  # Stop and unload the module from node
  #
  def unload(module_id : String)
    driver_key = driver_key_for?(module_id)
    ::Log.with_context(driver_key: driver_key, module_id: module_id) do
      stop(module_id)

      existing_manager = set_module_protocol_manager(module_id, nil)

      Log.info { "unloaded module" }

      no_module_references = (existing_manager.nil? || protocol_manager_lock.synchronize {
        @module_protocol_managers.none? do |_, manager|
          manager == existing_manager
        end
      })

      # Delete driver indexed manager if there are no other module references.
      if driver_key && no_module_references
        remove_driver_manager(driver_key)
        Log.info { "no modules for driver after unloading module" }
      end
    end
  rescue exception
    raise module_error(module_id, exception)
  end

  def kill(driver_key : String) : Bool
    !!protocol_manager_by_driver?(driver_key).try do |manager|
      pid = manager.pid
      Process.signal(Signal::KILL, pid)
      true
    end
  rescue
    false
  end

  def debug(module_id : String, &on_message : DebugCallback)
    manager = protocol_manager_by_module?(module_id)
    raise ModuleError.new("No protocol manager for #{module_id}") if manager.nil?

    manager.debug(module_id, &on_message)
  rescue exception
    raise module_error(module_id, exception)
  end

  def ignore(module_id : String, &on_message : DebugCallback)
    return if (manager = protocol_manager_by_module?(module_id)).nil?
    manager.ignore(module_id, &on_message)
  rescue exception
    raise module_error(module_id, exception)
  end

  def ignore(module_id : String) : Array(DebugCallback)
    return [] of DebugCallback if (manager = protocol_manager_by_module?(module_id)).nil?
    manager.ignore_all(module_id)
  rescue exception
    raise module_error(module_id, exception)
  end

  # Metadata
  #############################################################################################

  def system_status : SystemStatus
    process = Hardware::PID.new
    memory = Hardware::Memory.new
    cpu = Hardware::CPU.new

    core_cpu = process.stat.cpu_usage!
    total_cpu = cpu.usage!

    # 0 utilization for NaNs
    core_cpu = 0_f64 if core_cpu.nan?
    total_cpu = 0_f64 if total_cpu.nan?
    core_cpu = 100_f64 if core_cpu.infinite?
    total_cpu = 100_f64 if total_cpu.infinite?

    SystemStatus.new(
      hostname: System.hostname,
      cpu_count: System.cpu_count,
      core_cpu: core_cpu,
      total_cpu: total_cpu,
      memory_total: memory.total,
      memory_usage: memory.used,
      core_memory: memory.used,
    )
  end

  def driver_status(driver_key : String) : DriverStatus?
    manager = protocol_manager_by_driver?(driver_key)
    return if manager.nil?

    # Obtain process statistics - anything that might be useful for debugging
    if manager.running?
      process = Hardware::PID.new(manager.pid)
      memory = Hardware::Memory.new

      percentage_cpu = process.stat.cpu_usage!
      # 0 utilization for NaNs
      percentage_cpu = 0_f64 if percentage_cpu.nan?
      percentage_cpu = 100_f64 if percentage_cpu.infinite?
      memory_total = memory.total.to_i64
      memory_usage = process.memory.to_i64
    end

    DriverStatus.new(
      running: manager.running?,
      module_instances: manager.module_instances.to_i32,
      last_exit_code: manager.last_exit_code,
      launch_count: manager.launch_count,
      launch_time: manager.launch_time,
      percentage_cpu: percentage_cpu,
      memory_total: memory_total,
      memory_usage: memory_usage,
    )
  end

  def module_loaded?(module_id : String) : Bool
    !protocol_manager_by_module?(module_id).nil?
  end

  def driver_loaded?(driver_key : String) : Bool
    !protocol_manager_by_driver?(driver_key).nil?
  end

  def run_count : Count
    protocol_manager_lock.synchronize do
      Count.new(@driver_protocol_managers.size, @module_protocol_managers.size)
    end
  end

  # Map reduce the querying of what modules are loaded on running drivers
  #
  def loaded_modules : Hash(String, Array(String))
    protocol_manager_lock.synchronize do
      Promise.all(@driver_protocol_managers.map { |driver_key, manager|
        Promise.defer do
          info = manager.info
          Log.trace { {info: manager.info.to_json, driver: driver_key} }
          {driver_key, info}
        end
      }).then(&.to_h).get
    end
  end

  # Protocol Managers
  ###########################################################################

  # HACK: Retrieve the driver path from the module_id
  def path_for?(module_id) : Path?
    driver_key_for?(module_id).try do |key|
      Path.new(Compiler.binary_dir, key)
    end
  end

  # HACK: Retrieve the driver key from the module_id
  def driver_key_for?(module_id) : String?
    protocol_manager_lock.synchronize do
      @module_protocol_managers[module_id]?.try do |manager|
        @driver_protocol_managers.key_for?(manager)
      end
    end
  end

  def remove_driver_manager(key)
    set_driver_protocol_manager(key, nil)
  end

  private getter protocol_manager_lock = Mutex.new(protection: :reentrant)

  # Mapping from module_id to protocol manager
  @module_protocol_managers : Hash(String, Driver::Protocol::Management) = {} of String => Driver::Protocol::Management

  # Mapping from driver path to protocol manager
  @driver_protocol_managers : Hash(String, Driver::Protocol::Management) = {} of String => Driver::Protocol::Management

  protected def protocol_manager_by_module?(module_id) : Driver::Protocol::Management?
    manager_by_key?(module_id, @module_protocol_managers)
  end

  protected def protocol_manager_by_driver?(driver_key) : Driver::Protocol::Management?
    manager_by_key?(ProcessManager.path_to_key(driver_key), @driver_protocol_managers)
  end

  private def manager_by_key?(key, managers)
    protocol_manager_lock.synchronize do
      managers[key]?.tap do |manager|
        Log.trace { "missing module manager for #{key}" } if manager.nil?
      end
    end
  end

  protected def set_module_protocol_manager(module_id, manager : Driver::Protocol::Management?)
    protocol_manager_lock.synchronize do
      Log.trace { {message: "#{manager.nil? ? "removing" : "setting"} module process manager", module_id: module_id} }
      if manager.nil?
        @module_protocol_managers.delete(module_id)
      else
        @module_protocol_managers[module_id] = manager
        manager
      end
    end
  end

  protected def set_driver_protocol_manager(driver_key, manager : Driver::Protocol::Management?)
    driver_key = ProcessManager.path_to_key(driver_key)
    protocol_manager_lock.synchronize do
      Log.trace { {message: "#{manager.nil? ? "removing" : "setting"} driver process manager", driver_key: driver_key} }
      if manager.nil?
        @driver_protocol_managers.delete(driver_key)
      else
        @driver_protocol_managers[driver_key] = manager
        manager
      end
    end
  end

  # Error handling
  #################################################################################################

  macro module_error(module_id, exception)
    if {{ exception }}.is_a?(ModuleError)
      {{ exception }}
    else
      %driver_path = path_for?({{ module_id }})
      %context = [] of String
      %context << "module manager not present" unless protocol_manager_by_module?({{ module_id }})
      %context << "driver expected at #{%driver_path} not present" if %driver_path && !File.exists?(%driver_path)
      %message = "When invoking {{@def.name}} on #{{{module_id}}} #{%context.join(", ")}"
      ModuleError.new(%message, cause: {{ exception }})
    end
  end
end
