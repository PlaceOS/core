require "promise"
require "pg-orm"

module PlaceOS::Core::Healthcheck
  def self.healthcheck? : Bool
    Promise.all(
      Promise.defer {
        check_resource?("redis") { ::PlaceOS::Driver::RedisStorage.with_redis &.ping }
      },
      Promise.defer {
        check_resource?("postgres") { pg_healthcheck }
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

  private def self.pg_healthcheck
    ::DB.connect(pg_healthcheck_url) do |db|
      db.query_all("select datname from pg_stat_activity where datname is not null", as: {String}).first?
    end
  end

  @@pg_healthcheck_url : String? = nil

  private def self.pg_healthcheck_url(timeout = 5)
    @@pg_healthcheck_url ||= begin
      url = PgORM::Settings.to_uri
      uri = URI.parse(url)
      if q = uri.query
        params = URI::Params.parse(q)
        unless params["timeout"]?
          params.add("timeout", timeout.to_s)
        end
        uri.query = params.to_s
        uri.to_s
      else
        "#{url}?timeout=#{timeout}"
      end
    end
  end
end
