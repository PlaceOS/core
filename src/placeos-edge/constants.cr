require "action-controller/logger"

module PlaceOS::Edge
  APP_NAME = "PlaceOS Edge"
  VERSION  = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  # Secret used to register with PlaceOS
  CLIENT_SECRET = ENV["PLACE_EDGE_KEY"]?.try { |t| decode_token(t) } || (production? ? abort("missing PLACE_EDGE_KEY in environment") : "edge-1000_secret")

  # URI of PlaceOS instance
  PLACE_URI = URI.parse(ENV["PLACE_URI"]? || "http://localhost:6000".tap { |v| Log.warn { "missing PLACE_URI in environment, using #{v}" } })

  PROD = ENV["SG_ENV"]? == "production"

  LOG_STDOUT = ActionController.default_backend
  Log        = ::Log.for(self)

  def self.production?
    PROD
  end

  protected def self.decode_token(token)
    # Token is in the form hash.secret so validate the two parts best we can
    # Using string length is a bit shit but not sure how else we can do
    parts = token.split(".")
    raise "malformed Token" if parts[0].size != 32
    raise "malformed Token" if parts[1].size != 43
    token if token.presence
  rescue ex
    Log.error { ex.message }
    nil
  end
end
