require "./logging"
require "placeos-log-backend/telemetry"

module PlaceOS::Core
  PlaceOS::LogBackend.configure_opentelemetry(
    service_name: APP_NAME,
    service_version: VERSION,
  )
end
