require "./application"
require "placeos-models/version"

require "rethinkdb"
require "rethinkdb-orm"

module PlaceOS::Core::Api
  class Root < Application
    base "/api/core/v1/"

    class_getter resource_manager : ResourceManager { ResourceManager.instance }
    class_getter module_manager : ModuleManager { ModuleManager.instance }

    # Health Check
    ###############################################################################################

    def index
      head self.class.healthcheck? ? HTTP::Status::OK : HTTP::Status::INTERNAL_SERVER_ERROR
    end

    get "/version", :version do
      render :ok, json: PlaceOS::Model::Version.new(
        version: VERSION,
        build_time: BUILD_TIME,
        commit: BUILD_COMMIT,
        service: APP_NAME
      )
    end

    def self.healthcheck? : Bool
      Promise.all(
        Promise.defer {
          check_resource?("redis") { ::PlaceOS::Driver::RedisStorage.with_redis &.ping }
        },
        Promise.defer {
          check_resource?("etcd") { module_manager.discovery.etcd &.maintenance.status }
        },
        Promise.defer {
          check_resource?("rethinkdb") { rethinkdb_healthcheck }
        },
      ).then(&.all?).get
    end

    private def self.check_resource?(resource)
      Log.trace { "healthchecking #{resource}" }
      !!yield
    rescue exception
      Log.error(exception: exception) { {"connection check to #{resource} failed"} }
      false
    end

    private class_getter rethinkdb_admin_connection : RethinkDB::Connection do
      RethinkDB.connect(
        host: RethinkORM.settings.host,
        port: RethinkORM.settings.port,
        db: "rethinkdb",
        user: RethinkORM.settings.user,
        password: RethinkORM.settings.password,
        max_retry_attempts: 1,
      )
    end

    private def self.rethinkdb_healthcheck
      RethinkDB
        .table("server_status")
        .pluck("id", "name")
        .run(rethinkdb_admin_connection)
        .first?
    end

    # Readiness Check
    ###############################################################################################

    get("/ready") do
      head self.class.ready? ? HTTP::Status::OK : HTTP::Status::SERVICE_UNAVAILABLE
    end

    def self.ready?
      resource_manager.started?.tap do |ready|
        Log.warn { "startup has not completed" } unless ready
      end
    end
  end
end
