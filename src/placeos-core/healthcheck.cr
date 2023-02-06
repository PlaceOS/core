require "promise"
require "rethinkdb"
require "rethinkdb-orm"

module PlaceOS::Core::Healthcheck
  def self.healthcheck? : Bool
    Promise.all(
      Promise.defer {
        check_resource?("redis") { ::PlaceOS::Driver::RedisStorage.with_redis &.ping }
      },
      Promise.defer {
        check_resource?("etcd") { ModuleManager.instance.discovery.etcd(&.maintenance.status) }
      },
      Promise.defer {
        check_resource?("rethinkdb") { rethinkdb_healthcheck }
      },
    ).then(&.all?).get
  end

  private def self.check_resource?(resource, &)
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
end
