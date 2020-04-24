# Application dependencies
require "action-controller"

# Required to convince Crystal this class is not a module
abstract class PlaceOS::Driver; end

class PlaceOS::Driver::Protocol; end

# Application code
require "driver/protocol/management"
require "./constants"
require "./core"
require "./controllers/*"

# Server required after application controllers
require "action-controller/server"

# Path to driver repositories
PlaceOS::Drivers::Compiler.repository_dir = ENV["ENGINE_REPOS"]? || Path["./repositories"].expand.to_s
# Path to default drivers repository
PlaceOS::Drivers::Compiler.drivers_dir = ENV["ENGINE_DRIVERS"]? || File.join(PlaceOS::Drivers::Compiler.repository_dir, "drivers")

# Configure Service discovery
HoundDog.configure do |settings|
  settings.service_namespace = "core"
  settings.etcd_host = ENV["ETCD_HOST"]? || "localhost"
  settings.etcd_port = (ENV["ETCD_PORT"]? || 2379).to_i
end

PROD = ENV["SG_ENV"]? == "production"

# Filter out sensitive params that shouldn't be logged
filter_params = ["password", "bearer_token"]

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(PROD),
  ActionController::LogHandler.new(PROD ? filter_params : nil),
  HTTP::CompressHandler.new
)

# Configure logging
log_level = PROD ? Log::Severity::Info : Log::Severity::Debug
Log.builder.bind "*", :warning, PlaceOS::Core::LOG_BACKEND
Log.builder.bind "action-controller.*", log_level, PlaceOS::Core::LOG_BACKEND
Log.builder.bind "#{PlaceOS::Core::APP_NAME}.*", log_level, PlaceOS::Core::LOG_BACKEND
