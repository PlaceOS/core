# Application dependencies
require "action-controller"

# Required to convince Crystal this class is not a module
# :nodoc:
abstract class PlaceOS::Driver; end

# :nodoc:
class PlaceOS::Driver::Protocol; end

# Application code
require "./constants"
require "./placeos-core"
require "./controllers/*"

# Server required after application controllers
require "action-controller/server"

# Path to driver repositories
PlaceOS::Compiler.repository_dir = PlaceOS::Core::REPOS
# Path to default drivers repository
PlaceOS::Compiler.drivers_dir = PlaceOS::Core::DRIVERS

# Configure Service discovery
HoundDog.configure do |settings|
  settings.service_namespace = "core"
  settings.etcd_host = PlaceOS::Core::ETCD_HOST
  settings.etcd_port = PlaceOS::Core::ETCD_PORT
end

# Filter out sensitive params that shouldn't be logged
filter_params = ["password", "bearer_token"]

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(PlaceOS::Core.production?),
  ActionController::LogHandler.new(filter_params)
)

# Configure logging
log_level = PlaceOS::Core.production? ? Log::Severity::Info : Log::Severity::Debug
::Log.setup "*", log_level, PlaceOS::Core::LOG_BACKEND
::Log.builder.bind "action-controller.*", log_level, PlaceOS::Core::LOG_BACKEND
::Log.builder.bind "place_os.core.*", log_level, PlaceOS::Core::LOG_BACKEND
