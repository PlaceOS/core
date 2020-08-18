require "secrets-env"

module PlaceOS::Core
  APP_NAME     = "core"
  API_VERSION  = "v1"
  VERSION      = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  BUILD_TIME   = {{ system("date -u").stringify }}
  BUILD_COMMIT = {{ env("PLACE_COMMIT") || "DEV" }}

  REPOS   = ENV["ENGINE_REPOS"]? || Path["./repositories"].expand.to_s
  DRIVERS = ENV["ENGINE_DRIVERS"]? || File.join(PlaceOS::Compiler.repository_dir, "drivers")

  ETCD_HOST = ENV["ETCD_HOST"]? || "localhost"
  ETCD_PORT = (ENV["ETCD_PORT"]? || 2379).to_i

  REDIS_URL = ENV["REDIS_URL"]?

  PROD = ENV["SG_ENV"]? == "production"

  def self.production?
    PROD
  end

  # NOTE:: these are used in files that are included in other projects
  # ENV["CORE_HOST"]
  # ENV["CORE_PORT"]
  # ENV["REDIS_URL"]
  # ./placeos-core/module_manager.cr
  # ./placeos-core/client.cr
end
