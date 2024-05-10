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
      spawn(same_thread: true) { module_manager.start }
      Fiber.yield
    end
  end

  # Wait for the upstream services to be ready
  # - redis
  # - postgres
  def self.wait_for_resources
    Retriable.retry(
      max_elapsed_time: 1.minutes,
      on_retry: ->(_e : Exception, n : Int32, _t : Time::Span, _i : Time::Span) {
        Log.warn { "attempt #{n} connecting to services" }
      }
    ) do
      # Ensure services are reachable and healthy
      raise "retry" unless Healthcheck.healthcheck?
    end
  rescue
    abort("Upstream services are unavailable")
  end
end
