require "placeos-log-backend"

require "./constants"

module PlaceOS::Core::Logging
  ::Log.progname = APP_NAME

  # Configure logging
  namespaces = ["action-controller.*", "place_os.*"]
  log_backend = PlaceOS::LogBackend.log_backend
  log_level = Core.production? ? ::Log::Severity::Info : ::Log::Severity::Debug

  builder = ::Log.builder

  ::Log.setup_from_env(
    default_level: log_level,
    builder: builder,
    backend: log_backend,
    log_level_env: "LOG_LEVEL",
  )

  builder.bind "*", log_level, log_backend
  namespaces.each do |namespace|
    builder.bind(namespace, log_level, log_backend)
  end

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: Core.production?,
    namespaces: namespaces,
    backend: log_backend,
  )
end
