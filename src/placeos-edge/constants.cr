require "action-controller/logger"

module PlaceOS::Edge
  APP_NAME = "PlaceOS Edge"
  VERSION  = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  # Secret used to register with PlaceOS
  CLIENT_SECRET = ENV["PLACE_EDGE_KEY"]? || (production? ? abort("missing PLACE_EDGE_KEY in environment") : "edge-1000_secret")
  EDGE_ID       = ENV["PLACE_EDGE_ID"]? || "placeos-edge"

  # URI of PlaceOS instance
  PLACE_URI              = URI.parse(ENV["PLACE_URI"]? || "https://localhost:8443".tap { |v| Log.warn { "missing PLACE_URI in environment, using #{v}" } })
  SNAPSHOT_POLL_INTERVAL = (ENV["PLACE_EDGE_POLL_INTERVAL"]?.try(&.to_i?) || 5).seconds

  # Backpressure limits for offline operation
  MAX_PENDING_UPDATES = (ENV["PLACE_EDGE_MAX_PENDING_UPDATES"]?.try(&.to_i?) || 10_000)
  MAX_PENDING_EVENTS  = (ENV["PLACE_EDGE_MAX_PENDING_EVENTS"]?.try(&.to_i?) || 1_000)

  PROD = ENV["SG_ENV"]? == "production"

  LOG_STDOUT = ActionController.default_backend
  Log        = ::Log.for(self)

  def self.production?
    PROD
  end
end
