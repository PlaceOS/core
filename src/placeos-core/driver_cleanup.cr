require "file_utils"
require "pg-orm"
require "redis"
require "time"

module PlaceOS::Core::DriverCleanup
  def self.start_cleanup
    spawn do
      tracker = StaleProcessTracker.new(DriverStore::BINARY_PATH, REDIS_CLIENT)
      loop do
        sleep(ENV["STALE_SCAN_INTERVAL"]?.try &.to_i.hours || (23.hours + rand(60).minutes))
        stale_list = tracker.update_and_find_stale(ENV["STALE_THRESHOLD_DAYS"]?.try &.to_i || 30)
        tracker.delete_stale_executables(stale_list)
      end
    end
  end

  def self.arch
    {% if flag?(:x86_64) %} "amd64" {% elsif flag?(:aarch64) %} "arm64" {% end %} || raise("Uknown architecture")
  end

  class StaleProcessTracker
    Log = Core::Log

    def initialize(@folder : String, @redis : Redis::Client)
      @now = Time.utc
    end

    def update_and_find_stale(days_threshold : Int32 = 30)
      Log.info { "Starting stale executable check for #{@folder}" }

      current_executables = get_current_executables
      Log.debug { "Found #{current_executables.size} executables in folder" }

      # Register new executables and update tracking
      track_execution_events(current_executables)

      # Identify stale binaries considering both discovery and execution time
      find_stale_binaries(current_executables, days_threshold.days)
    end

    private def get_current_executables
      Dir.children(@folder)
        .map { |f| File.join(@folder, f) }
        .select { |f| File.file?(f) && File::Info.executable?(f) }
        .to_set
    end

    def delete_stale_executables(stale_list : Array(String)) : Nil
      Log.info { "Starting deletion of #{stale_list.size} stale executables" }

      stale_list.each do |exe_path|
        begin
          if File.exists?(exe_path)
            File.delete(exe_path)
            Log.info { "Deleted file: #{exe_path}" }
          else
            Log.warn { "File not found, skipped deletion: #{exe_path}" }
          end

          deleted_count = @redis.del(exe_path)
          if deleted_count > 0
            Log.debug { "Removed Redis entry for: #{exe_path}" }
          else
            Log.warn { "No Redis entry found for: #{exe_path}" }
          end
        rescue ex : Errno
          Log.error(exception: ex) { "Failed to delete #{exe_path}" }
        end
      end

      Log.info { "Completed deletion process" }
    end

    private def track_execution_events(current_executables)
      # Register new executables with discovery time
      current_executables.each do |exe|
        unless @redis.hexists(exe, "discovered_at")
          @redis.hset(exe, "discovered_at", @now.to_unix)
        end
      end

      # Update execution times for running processes
      update_running_processes(current_executables)
    end

    private def update_running_processes(current_executables)
      current_uid = LibC.getuid
      folder_basenames = current_executables.map { |exe| File.basename(exe) }.to_set

      Dir.glob("/proc/[0-9]*").each do |pid_dir|
        begin
          next unless process_owned_by_current_user?(pid_dir, current_uid)

          exe_name = get_process_executable_name(pid_dir)
          next unless exe_name && folder_basenames.includes?(exe_name)

          full_path = File.join(@folder, exe_name)
          next unless current_executables.includes?(full_path)

          # Update last execution time
          @redis.hset(full_path, "last_executed_at", @now.to_unix)
        rescue
          # Ignore permission issues and race conditions
        end
      end
    end

    private def find_stale_binaries(current_executables, threshold)
      cutoff = @now - threshold
      stale = [] of String

      current_executables.each do |exe|
        redis_data = @redis.hgetall(exe)
        discovered_at = redis_data["discovered_at"]?.try(&.to_i64)
        last_executed_at = redis_data["last_executed_at"]?.try(&.to_i64)

        # Determine reference time (last execution or discovery)
        reference_time = if lea = last_executed_at
                           Time.unix(lea)
                         elsif da = discovered_at
                           Time.unix(da)
                         else
                           @now # Should never happen due to registration
                         end

        if (@now - reference_time) > threshold
          stale << exe
        end
      end
      Log.info { "Found #{stale.size} stale executables" }
      Log.debug { "Stale list: #{stale.join(", ")}" } unless stale.empty?
      stale
    end

    private def process_owned_by_current_user?(pid_dir : String, current_uid : UInt32) : Bool
      status_file = File.join(pid_dir, "status")
      return false unless File.exists?(status_file)

      uid_line = File.read(status_file).split("\n").find(&.starts_with?("Uid:"))
      return false unless uid_line

      process_uid = uid_line.split(/\s+/)[1].to_i
      process_uid == current_uid
    end

    private def get_process_executable_name(pid_dir : String) : String?
      cmdline = File.read(File.join(pid_dir, "cmdline")).split("\0").first?
      return unless cmdline

      File.basename(cmdline)
    rescue
      nil
    end
  end
end
