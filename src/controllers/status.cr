require "./application"
require "hardware"
require "engine-drivers/helper"

module Engine::Core
  class Status < Application
    base "/api/core/v1/status/"
    id_param :commit_hash

    # TODO:: lookup the driver manager in a global dispatch
    # This needs to exist somewhere
    DriverExecLookup = {} of String => EngineDriver::Protocol::Management

    # General statistics related to the process
    def index
      helper = EngineDrivers::Helper

      render json: {
        compiled_drivers: helper.compiled_drivers,
        available_repositories: helper.repositories,

        # TODO::
        running_drivers: DriverExecLookup.size,
        module_instances: 200, # ModuleExecLookup.size
        unavailable_repositories: [{
          name: "private_1",
          reason: "401 unauthorised while cloning"
        }],
        unavailable_drivers: [{
          name: "Cisco XXX",
          reason: "failed to compile / failed to run"
        }]
      }
    end

    # details related to a process (+ anything else we can think of)
    # /api/core/v1/status/driver?path=/path/to/compiled_driver
    get "/driver" do
      driver = params["path"]
      manager = DriverExecLookup[driver]?
      head :not_found unless manager

      response = {
        running: manager.running?,
        module_instances: manager.module_instances,
        last_exit_code: manager.last_exit_code,
        launch_count: manager.launch_count,
        launch_time: manager.launch_time
      }

      # Obtain process statistics - anything that might be useful for debugging
      if manager.running?
        process = Hardware::PID.new(manager.pid)
        memory = Hardware::Memory.new

        response = response.merge({
          # CPU in % and memory in KB
          percentage_cpu: process.cpu_usage,
          memory_total: memory.total,
          memory_usage: process.memory,
        })
      end

      render json: response
    end

    # details about the overall machine load
    get "/load" do
      process = Hardware::PID.new
      memory = Hardware::Memory.new
      cpu = Hardware::CPU.new

      render json: {
        # These will be the values in the container but that's all good
        hostname: System.hostname,
        cpu_count: System.cpu_count,

        # these are as a percent of the total available
        core_cpu: process.cpu_usage,
        total_cpu: cpu.usage,

        # Memory in KB
        memory_total: memory.total,
        memory_usage: memory.used,
        core_memory: memory.used
      }
    end
  end
end
