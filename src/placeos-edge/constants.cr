require "action-controller/logger"

module PlaceOS::Edge
  APP_NAME = "PlaceOS Edge"
  VERSION  = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  # Secret used to register with PlaceOS
  CLIENT_SECRET = ENV["PLACE_EDGE_SECRET"]? || abort "missing PLACE_EDGE_SECRET in environment"

  # URI of PlaceOS instance
  PLACE_URI = URI.parse(ENV["PLACE_URI"]? || abort "missing PLACE_HOST in environment")

  PROD = ENV["SG_ENV"]? == "production"

  LOG_BACKEND = ActionController.default_backend
  Log         = ::Log.for(self)

  def self.production?
    PROD
  end
end
