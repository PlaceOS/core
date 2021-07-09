# Application dependencies
require "action-controller"

# Required to convince Crystal this class is not a module

# :nodoc:
abstract class PlaceOS::Driver; end

# :nodoc:
class PlaceOS::Driver::Protocol; end

# Application code
require "./logging"
require "./constants"

require "./placeos-core"
require "./api/*"

# Server required after application controllers
require "action-controller/server"

# Path to driver repositories
PlaceOS::Compiler.repository_dir = PlaceOS::Core::REPOS

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
  ActionController::LogHandler.new(filter_params, ms: true)
)
