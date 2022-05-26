require "./logging"
require "opentelemetry-instrumentation/src/opentelemetry/instrumentation/instrument"
require "placeos-log-backend/telemetry"
require "placeos-resource/instrumentation"

module PlaceOS::Core
  PlaceOS::LogBackend.configure_opentelemetry(
    service_name: APP_NAME,
    service_version: VERSION,
  )
end
