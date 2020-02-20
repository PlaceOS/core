require "hardware"
require "engine-drivers/helper"

require "./application"
require "../engine-core/module_manager"
require "../engine-core/resource_manager"

module ACAEngine::Core::Api
  class Status < Application
    base "/api/core/v1/status/"
    id_param :commit_hash

    getter module_manager = ModuleManager.instance
    getter resource_manager = ResourceManager.instance

    # General statistics related to the process
    def index
      render json: {
        compiled_drivers:         ACAEngine::Drivers::Helper.compiled_drivers,
        available_repositories:   ACAEngine::Drivers::Helper.repositories,
        running_drivers:          module_manager.running_drivers,
        module_instances:         module_manager.running_modules,
        unavailable_repositories: resource_manager.cloning.errors,
        unavailable_drivers:      resource_manager.compilation.errors,
      }
    end

    # details related to a process (+ anything else we can think of)
    # /api/core/v1/status/driver?path=/path/to/compiled_driver
    get "/driver", :driver do
      driver_path = params["path"]?
      head :unprocessable_entity unless driver_path

      manager = module_manager.manager_by_driver_path(driver_path)
      head :not_found unless manager

      response = {
        running:          manager.running?,
        module_instances: manager.module_instances,
        last_exit_code:   manager.last_exit_code,
        launch_count:     manager.launch_count,
        launch_time:      manager.launch_time,
      }

      # Obtain process statistics - anything that might be useful for debugging
      if manager.running?
        process = Hardware::PID.new(manager.pid)
        memory = Hardware::Memory.new

        response = response.merge({
          # CPU in % and memory in KB
          percentage_cpu: process.stat.cpu_usage!,
          memory_total:   memory.total,
          memory_usage:   process.memory,
        })
      end

      render json: response
    end

    # details about the overall machine load
    get "/load", :load do
      process = Hardware::PID.new
      memory = Hardware::Memory.new
      cpu = Hardware::CPU.new

      render json: {
        # These will be the values in the container but that's all good
        hostname:  System.hostname,
        cpu_count: System.cpu_count,

        # these are as a percent of the total available
        core_cpu:  process.stat.cpu_usage!,
        total_cpu: cpu.usage,

        # Memory in KB
        memory_total: memory.total,
        memory_usage: memory.used,
        core_memory:  memory.used,
      }
    end

    # Overriding initializers for dependency injection
    ###########################################################################

    def initialize(@context, @action_name = :index, @__head_request__ = false)
      super(@context, @action_name, @__head_request__)
    end

    def initialize(
      context : HTTP::Server::Context,
      action_name = :index,
      @module_manager : ModuleManager = ModuleManager.instance,
      @resource_manager : ResourceManager = ResourceManager.instance
    )
      super(context, action_name)
    end
  end
end
