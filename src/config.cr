# Application dependencies
require "action-controller"
PROD = ENV["SG_ENV"]? == "production"

# Allows request IDs to be configured for logging
# You can extend this with additional properties
ActionController::Logger.add_tag request_id
filter_params = ["bearer_token", "password"]
logger = ActionController::Base.settings.logger
logger.level = PROD ? Logger::INFO : Logger::DEBUG

# For some reason I could not convince Crystal this was not a module without
# putting it here
abstract class ACAEngine::Driver; end

class ACAEngine::Driver::Protocol; end

# Application code
require "engine-driver/protocol/management"
require "./constants"
require "./controllers/application"
require "./controllers/*"
require "./engine-core"

# Server required after application controllers
require "action-controller/server"

# Configure Service discovery
HoundDog.configure do |settings|
  settings.logger = ActionController::Base.settings.logger
  settings.etcd_host = ENV["ETCD_HOST"]? || "localhost"
  settings.etcd_port = (ENV["ETCD_PORT"]? || 2379).to_i
end

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(!PROD),
  ActionController::LogHandler.new(filter_params),
  HTTP::CompressHandler.new
)

# Optional support for serving of static assests
static_file_path = ENV["PUBLIC_WWW_PATH"]? || "./www"
if File.directory?(static_file_path)
  # Optionally add additional mime types
  ::MIME.register(".yaml", "text/yaml")

  # Check for files if no paths matched in your application
  ActionController::Server.before(
    ::HTTP::StaticFileHandler.new(static_file_path, directory_listing: false)
  )
end

# Configure session cookies
# NOTE:: Change these from defaults
ActionController::Session.configure do |settings|
  settings.key = ENV["COOKIE_SESSION_KEY"]? || "_spider_gazelle_"
  settings.secret = ENV["COOKIE_SESSION_SECRET"]? || "4f74c0b358d5bab4000dd3c75465dc2c"
  # HTTPS only:
  settings.secure = PROD
end
