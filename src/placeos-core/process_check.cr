require "tasker"
require "timeout"

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

    # TODO:
    # Add `with_module_managers` to ProcessManager interface
    # and thus provide process check support for edge nodes.
    #
    # NOTE: This could also be performed independently in the `Edge::Client` instead of here.
    protected def process_check : Nil
      Log.debug { "checking for dead driver processes" }

      # NOTE: Add `edge_processes` here once it supports process check
      {local_processes}.each &.with_module_managers do |module_manager_map|
        # Group module keys by protcol manager
        grouped_managers = module_manager_map.each_with_object({} of Driver::Protocol::Management => Array(String)) do |(module_id, protocol_manager), grouped|
          (grouped[protocol_manager] ||= [] of String) << module_id
        end

        # Check if any processes are dead
        grouped_managers.each do |protocol_manager, module_ids|
          # Asynchronously check if any processes are timing out on comms, and if so, restart them
          spawn(same_thread: true) do
            process_alive = begin
              # If there's an empty response, the modules that were meant to be running are not.
              # This is taken as a sign that the process is dead.
              # Alternatively, if the response times out, the process is dead.
              timeout(PROCESS_COMMS_TIMEOUT) do
                !protocol_manager.info.empty?
              end
            rescue error
              Log.warn(exception: error) { "unresponsive process manager for #{module_ids.join(", ")}" }
              false
            end

            unless process_alive
              Log.warn { {message: "restarting unresponsive driver", driver_path: protocol_manager.@driver_path} }
              # Ensure the process is dead.
              begin
                Process.signal(Signal::KILL, protocol_manager.pid)
              rescue
              end

              # Remove the dead manager from the map
              module_manager_map.reject(module_ids)

              # Restart all the modules previously assigned to the dead manager
              #
              # TODO:
              # Make this independent of a database query by using the dead manager's stored module_ids and payloads.
              # This will allow this module to be included in `PlaceOS::Edge::Client`.
              # To do so, one will need to create the module manager (currently done by the `load_module` below (which is in `PlaceOS::Core::ModuleManager`))
              Model::Module.find_all(module_ids).each do |mod|
                load_module(mod)
              end
            end
          end
        end
      end
    end
  end
end
