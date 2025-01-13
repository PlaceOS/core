require "action-controller/logger"
# fixes issues with static builds on crystal 1.5.x
require "placeos-driver/core_ext"
require "log_helper"

require "./placeos-core/*"
require "./constants"

module PlaceOS::Core
  # Minimize the number of connections being made to redis
  REDIS_LOCK   = Driver::RedisStorage.redis_lock
  REDIS_CLIENT = Driver::RedisStorage.shared_redis_client

  def self.start_managers
    resource_manager = ResourceManager.instance
    module_manager = ModuleManager.instance

    # Acquire resources on startup
    resource_manager.start do
      # Start managing modules once relevant resources present
      spawn { module_manager.start }
      Fiber.yield
    end
  end

  # Wait for the upstream services to be ready
  # - redis
  # - postgres
  def self.wait_for_resources
    attempt = 0
    SimpleRetry.try_to(
      base_interval: 1.second,
      max_elapsed_time: 1.minute
    ) do
      # Ensure services are reachable and healthy
      attempt += 1
      Log.warn { "attempt #{attempt} connecting to services" } if attempt > 1
      raise "retry" unless Healthcheck.healthcheck?
    end
  rescue
    abort("Upstream services are unavailable")
  end
end
