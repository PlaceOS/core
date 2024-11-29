require "file_utils"
require "pg-orm"

module PlaceOS::Core::DriverCleanup
  def self.start_cleanup
    spawn do
      loop do
        sleep(23.hours + rand(60).minutes)
        cleanup_unused_drivers rescue nil
      end
    end
  end

  def self.cleanup_unused_drivers
    local = Dir.new(DriverStore::BINARY_PATH).children
    running = running_drivers
    stale = local - running
    FileUtils.rm_rf(stale.map { |file| Path[DriverStore::BINARY_PATH, file] }) unless stale.empty?
  end

  def self.arch
    {% if flag?(:x86_64) %} "amd64" {% elsif flag?(:aarch64) %} "arm64" {% end %} || raise("Uknown architecture")
  end

  def self.running_drivers
    sql = <<-SQL
    SELECT DISTINCT ON (driver.commit)
    regexp_replace(regexp_replace(driver.file_name, '.cr$', '', 'g'), '[/.]', '_', 'g') || '_' || LEFT(driver.commit, 6) || '_' AS driver_file
    FROM
        mod,
        driver
    WHERE
        mod.running = true
        AND driver.id = mod.driver_id
    ORDER BY driver.commit;
    SQL
    running =
      ::DB.connect(Healthcheck.pg_healthcheck_url) do |db|
        db.query_all sql, &.read(String)
      end
    running.map(&.+(arch))
  end
end
