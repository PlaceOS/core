require "action-controller/logger"
require "log_helper"

require "./placeos-core/*"
require "./constants"

module PlaceOS::Core
  Log           = ::Log.for(self)
  LOG_STDOUT    = ActionController.default_backend
  LOGSTASH_HOST = ENV["LOGSTASH_HOST"]?
  LOGSTASH_PORT = ENV["LOGSTASH_PORT"]?

  def self.log_backend
    if !(logstash_host = LOGSTASH_HOST.presence).nil?
      logstash_port = LOGSTASH_PORT.try(&.to_i?) || abort("LOGSTASH_PORT is either malformed or not present in environment")

      # Logstash UDP Input
      logstash = UDPSocket.new
      logstash.connect logstash_host, logstash_port
      logstash.sync = false

      # debug at the broadcast backend level, however this will be filtered
      # by the bindings
      backend = ::Log::BroadcastBackend.new
      backend.append(LOG_STDOUT, :trace)
      backend.append(ActionController.default_backend(
        io: logstash,
        formatter: ActionController.json_formatter
      ), :trace)
      backend
    else
      LOG_STDOUT
    end
  end

  def self.start_managers
    resource_manager = ResourceManager.instance
    module_manager = ModuleManager.instance

    # Acquire resources on startup
    resource_manager.start do
      # Start managing modules once relevant resources present
      module_manager.start
    end
  end

  # Wait for the upstream services to be ready
  # - etcd
  # - redis
  # - rethinkdb
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
