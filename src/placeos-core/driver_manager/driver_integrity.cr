require "file_utils"
require "db"
require "tasker"
require "./driver_store"

module PlaceOS::Core::DriverIntegrity
  DEFAULT_SCAN_INTERVAL = 2.hours

  record DriverRecord, id : String, driver_file : String, file_name : String, commit : String, uri : String, branch : String, username : String?, password : String?, running : Bool do
    include DB::Serializable
  end
  @@tasker_inst : Tasker::Repeat(Nil)?

  def self.start_integrity_checker
    @@tasker_inst = Tasker.every(ENV["INTEGRITY_SCAN_INTERVAL"]?.try &.to_i.hours || DEFAULT_SCAN_INTERVAL) do
      sync_drivers
    end
  end

  def self.stop_integrity_checker
    @@tasker_inst.try &.cancel
  end

  def self.remove_blank_files
    empty_files = [] of String
    Dir.glob("#{DriverStore::BINARY_PATH}/**/*") do |driver|
      if File.file?(driver) && File.size(driver) == 0
        empty_files << driver
      end
    end
    FileUtils.rm_rf(empty_files) unless empty_files.empty?
  end

  def self.current_executables
    remove_blank_files
    Dir.children(DriverStore::BINARY_PATH)
      .select { |f| File.file?(f) && File::Info.executable?(f) }
      .to_set
  end

  def self.sync_drivers : Nil
    existing = current_executables
    drivers_arr = all_drivers
    db_drivers = drivers_arr.map { |rec| rec.driver_file + Core::ARCH }.to_set
    add_drivers = db_drivers - existing
    stale = existing - db_drivers
    FileUtils.rm_rf(stale.map { |file| Path[DriverStore::BINARY_PATH, file] }) unless stale.empty?
    add_drivers_obj = drivers_arr.select { |rec| (rec.driver_file + Core::ARCH).in?(add_drivers) }
    download_drivers(add_drivers_obj)
    load_running_modules(drivers_arr.select(&.running))
  end

  def self.all_drivers : Array(DriverRecord)
    sql = <<-SQL
    SELECT
      regexp_replace(regexp_replace(d.file_name, '.cr$', '', 'g'), '[/.]', '_', 'g')
        || '_' ||
        (CASE
          WHEN char_length(d.commit) >= 7 THEN LEFT(d.commit, 7)
          ELSE d.commit
        END) || '_' AS driver_file,
        d.id, d.file_name, d.commit, r.uri, r.branch,r.username, r.password, m.running
    FROM driver d
    JOIN repo r ON d.repository_id = r.id
    JOIN mod m ON d.id = m.driver_id
    WHERE d.compilation_output IS NULL
      AND r.has_runtime_error = false;
    SQL

    result = ::DB.connect(Healthcheck.pg_healthcheck_url) do |db|
      db.query_all sql, &.read(DriverRecord)
    end
    result
  end

  def self.load_running_modules(drivers : Array(DriverRecord))
    return if drivers.empty?
    should_be_running = drivers.map { |rec| rec.driver_file + Core::ARCH }.to_set
    drivers_delta = should_be_running - find_running_drivers
    return if drivers_delta.empty?
    drivers_to_start = drivers.select { |rec| (rec.driver_file + Core::ARCH).in?(drivers_delta) }
    module_manager = ModuleManager.instance
    drivers_to_start.each do |driver|
      module_manager.reload_modules(Model::Driver.find!(driver.id))
    end
  end

  def self.download_drivers(drivers : Array(DriverRecord))
    store = DriverStore.new
    drivers.each do |driver|
      next if store.built?(driver.file_name, driver.commit, driver.branch, driver.uri)
      store.compile(driver.file_name, driver.uri, driver.commit, driver.branch, false, driver.username, driver.password)
    end
  end

  def self.find_running_drivers : Set(String)
    running = Set(String).new

    Dir.each_child("/proc") do |entry|
      # Skip non-PID entries (process IDs are numeric)
      next unless entry =~ /^\d+$/

      pid = entry
      exe_path = "/proc/#{pid}/exe"
      begin
        target = File.readlink(exe_path)
        running << File.basename(target) if target.starts_with?(DriverStore::BINARY_PATH)
      rescue ex : Exception
        # Ignore processes we can't inspect
      end
    end
    running
  end
end
