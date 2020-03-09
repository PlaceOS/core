module PlaceOS::Core
  APP_NAME    = "core"
  API_VERSION = "v1"
  VERSION     = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
end
