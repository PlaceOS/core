require "secrets-env"

module PlaceOS::Core
  APP_NAME    = "core"
  API_VERSION = "v1"
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}
  BUILD_TIME   = {{ system("date -u").chomp.stringify }}
  BUILD_COMMIT = {{ env("PLACE_COMMIT") || "DEV" }}

  DRIVERS = ENV["ENGINE_DRIVERS"]? || File.join(PlaceOS::Compiler.repository_dir, "drivers")

  ETCD_HOST = ENV["ETCD_HOST"]? || "localhost"
  ETCD_PORT = (ENV["ETCD_PORT"]? || 2379).to_i

  REDIS_URL = ENV["REDIS_URL"]? || "redis://localhost:6379"

  # `core` self-registers to etcd with this information.
  # In k8s we can grab the Pod information from the environment
  # https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/#use-pod-fields-as-values-for-environment-variables
  CORE_HOST = ENV["CORE_HOST"]? || System.hostname
  CORE_PORT = (ENV["CORE_PORT"]? || "3000").to_i

  PROD = ENV["SG_ENV"]?.try(&.downcase) == "production"

  RESPONSE_CODE_HEADER = "Response-Code"

  class_getter? production : Bool = PROD

  # Used in `ModuleManager`
  PROCESS_CHECK_PERIOD  = (ENV["PLACE_CORE_PROCESS_CHECK_PERIOD"]?.try(&.to_i?) || 80).seconds
  PROCESS_COMMS_TIMEOUT = (ENV["PLACE_CORE_PROCESS_COMMS_TIMEOUT"]?.try(&.to_i?) || 40).seconds

  ARCH = {% if flag?(:x86_64) %}
           "amd64"
         {% elsif flag?(:aarch64) %}
           "arm64"
         {% else %}
            {% abort "unsupported architechture" %}
         {% end %}
  BUILD_HOST = ENV["BUILD_API_HOST"]? || "localhost"
  BUILD_PORT = (ENV["BUILD_API_PORT"]? || 3000).to_i

  class_getter build_host = "http://#{BUILD_HOST}:#{BUILD_PORT}"
end
