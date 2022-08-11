require "tasker"

require "../constants"

module PlaceOS::Core
  # Periodic Process Check
  module ProcessCheck
    @process_check_task : Tasker::Repeat(Nil)?

    # Begin scanning for dead driver processes
    protected def start_process_check
      @process_check_task = Tasker.every(PROCESS_CHECK_PERIOD) do
        process_check
      end
    end

    protected def stop_process_check
      @process_check_task.try &.cancel
    end

    enum State
      # Process is running
      Running
      # Process is not responding
      Unresponsive
    end

    # TODO:
    # This could also be performed independently in the `Edge::Client`.
    #
    # - Add `with_module_managers` to ProcessManager interface
    #
    # - Create a `load_module` method that works with `module_id`s, using the dead pm's module_id => payload hash.
    #   See the note in the method below on where to hook this in.
    #
    protected def process_check : Nil
      Log.debug { "checking for dead driver processes" }

      # NOTE:
      # Generally, having an unbounded channel is a bad idea, as it can cause deadlocks.
      # The ideal would be having a channel the size of the number of managers we're inspecting.
      checks = Channel({State, {Driver::Protocol::Management, Array(String)}}).new

      total_protocol_managers = local_processes.with_module_managers do |module_manager_map|
        # Group module keys by protcol manager
        grouped_managers = module_manager_map.each_with_object({} of Driver::Protocol::Management => Array(String)) do |(module_id, protocol_manager), grouped|
          (grouped[protocol_manager] ||= [] of String) << module_id
        end

        # Asynchronously check if any processes are timing out on comms, and if so, restart them
        grouped_managers.each do |protocol_manager, module_ids|
          # Asynchronously check if any processes are timing out on comms, and if so, restart them
          spawn(same_thread: true) do
            state = begin
              # If there's an empty response, the modules that were meant to be running are not.
              # This is taken as a sign that the process is dead.
              # Alternatively, if the response times out, the process is dead.
              Tasker.timeout(PROCESS_COMMS_TIMEOUT) do
                protocol_manager.info
              end

              State::Running
            rescue error : Tasker::Timeout
              Log.warn(exception: error) { "unresponsive process manager for #{module_ids.join(", ")}" }
              State::Unresponsive
            end

            checks.send({state, {protocol_manager, module_ids}})
          end
        end

        grouped_managers.size
      end

      local_processes.with_module_managers do |module_manager_map|
        # Synchronously handle restarting unresponsive/dead drivers
        total_protocol_managers.times do
          state, driver_state = checks.receive
          protocol_manager, module_ids = driver_state

          next if state.running?

          # Ensure the process is killed
          if state.unresponsive?
            Process.signal(Signal::KILL, protocol_manager.pid) rescue nil
          end

          # Kill the process manager's IO, unblocking any fibers waiting on a response
          protocol_manager.@io.try(&.close) rescue nil

          Log.warn { {message: "restarting unresponsive driver", state: state.to_s, driver_path: protocol_manager.@driver_path} }

          # Determine if any new modules have been loaded onto the driver that needs to be restarted
          fresh_module_ids = module_manager_map.compact_map do |module_id, pm|
            module_id if pm == protocol_manager
          end

          # Union of old and new module_ids
          module_ids |= fresh_module_ids

          # Remove the dead manager from the map
          module_manager_map.reject!(module_ids)

          # Restart all the modules previously assigned to the dead manager
          #
          # NOTE:
          # Make this independent of a database query by using the dead manager's stored module_ids and payloads.
          # This will allow this module to be included in `PlaceOS::Edge::Client`.
          # To do so, one will need to create the module manager (currently done by the `load_module` below (which is in `PlaceOS::Core::ModuleManager`))
          Model::Module.find_all(module_ids).each do |mod|
            Log.debug { "reloading #{mod.id} after restarting unresponsive driver" }
            load_module(mod)
          end
        end
      end

      checks.close
    end
  end
end
