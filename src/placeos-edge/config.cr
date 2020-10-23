require "log"

require "./constants"

module PlaceOS::Edge
  # Configure logging
  log_level = production? ? ::Log::Severity::Info : ::Log::Severity::Debug
  ::Log.setup "*", log_level, LOG_BACKEND
  ::Log.builder.bind "place_os.edge.*", log_level, LOG_BACKEND
end
