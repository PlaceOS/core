require "action-controller/logger"

module PlaceOS::Edge
  APP_NAME = "PlaceOS Edge"
  VERSION  = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  # Secret used to register with PlaceOS
  CLIENT_SECRET = ENV["PLACE_EDGE_SECRET"]?.try { |t| decode_token(t) } || (production? ? abort("missing PLACE_EDGE_SECRET in environment") : "edge-1000_secret")

  # URI of PlaceOS instance
  PLACE_URI = URI.parse(ENV["PLACE_URI"]? || "https://localhost:8443".tap { |v| Log.warn { "missing PLACE_URI in environment, using #{v}" } })

  PROD = ENV["SG_ENV"]? == "production"

  LOG_STDOUT = ActionController.default_backend
  Log        = ::Log.for(self)

  def self.production?
    PROD
  end

  protected def self.decode_token(token)
    String.new(Base64.decode(token)) if token.presence
  rescue
    Log.error { "malformed token" }
    nil
  end
end
