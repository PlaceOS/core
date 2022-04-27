require "placeos-log-backend"
require "placeos-log-backend/telemetry"

require "./constants"

module PlaceOS::Core::Logging
  ::Log.progname = APP_NAME

  # Configure logging
  log_backend = PlaceOS::LogBackend.log_backend
  log_level = Core.production? ? ::Log::Severity::Info : ::Log::Severity::Debug

  builder = ::Log.builder
  builder.bind "*", log_level, log_backend

  namespaces = ["action-controller.*", "place_os.*"]
  namespaces.each do |namespace|
    builder.bind(namespace, log_level, log_backend)
  end

  ::Log.setup_from_env(
    default_level: log_level,
    builder: builder,
    backend: log_backend,
    log_level_env: "LOG_LEVEL",
  )

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: Core.production?,
    namespaces: namespaces,
    backend: log_backend,
  )

  PlaceOS::LogBackend.configure_opentelemetry(
    service_name: APP_NAME,
    service_version: VERSION,
  )
end
