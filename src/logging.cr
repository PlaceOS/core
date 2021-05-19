require "placeos-log-backend"

require "./constants"

module PlaceOS::Core::Logging
  ::Log.progname = APP_NAME

  # Configure logging
  log_backend = PlaceOS::LogBackend.log_backend
  log_level = Core.production? ? ::Log::Severity::Info : ::Log::Severity::Debug

  ::Log.setup "*", :warn, log_backend

  namespaces = ["action-controller.*", "place_os.*"]
  namespaces.each do |namespace|
    ::Log.builder.bind(namespace, log_level, log_backend)
  end

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: Core.production?,
    namespaces: namespaces,
    backend: log_backend,
  )
end
