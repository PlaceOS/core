# Application dependencies
require "action-controller"

# Required to convince Crystal this class is not a module

# :nodoc:
abstract class PlaceOS::Driver; end

# :nodoc:
class PlaceOS::Driver::Protocol; end

# Application code
require "./placeos-core"
require "./logging"
require "./constants"

require "./api/*"

# Require telemetry after application code
require "./telemetry"

# Server required after application controllers
require "action-controller/server"

# Filter out sensitive params that shouldn't be logged
filter_params = ["password", "bearer_token"]

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(PlaceOS::Core.production?),
  ActionController::LogHandler.new(filter_params, ms: true)
)
