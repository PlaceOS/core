module ACAEngine::Core
  APP_NAME    = "engine-core"
  API_VERSION = "v1"
  VERSION     = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
end
