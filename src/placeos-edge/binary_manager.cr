require "http"
require "uri"
require "simple_retry"

require "../placeos-core/driver_manager"

module PlaceOS::Edge
  class BinaryManager
    Log = ::Log.for(self)

    DOWNLOAD_PATH  = "/api/core/v1/edge/%{edge_id}/drivers/%{driver_key}"
    MIN_FREE_SPACE = 100_000_000_i64 # 100MB minimum free space

    protected getter store : PlaceOS::Core::DriverStore
    private getter edge_id : String
    private getter base_uri : URI
    private getter secret : String

    def initialize(@edge_id : String, @base_uri : URI, @secret : String, @store : PlaceOS::Core::DriverStore = PlaceOS::Core::DriverStore.new)
    end

    def ensure_binary(driver_key : String, max_retries : Int32 = 3)
      path = store.path(driver_key).to_s
      return path if File.exists?(path) && valid_binary?(path)

      # Check available disk space before download
      check_disk_space(path)

      temp_path = "#{path}.download"

      begin
        SimpleRetry.try_to(
          max_attempts: max_retries,
          base_interval: 1.second,
          max_interval: 5.seconds
        ) do |attempt, error|
          if error
            Log.warn { "driver download retry #{attempt}/#{max_retries} for #{driver_key}: #{error.message}" }
            File.delete(temp_path) rescue nil
          end

          uri = base_uri.dup
          uri.path = DOWNLOAD_PATH % {edge_id: edge_id, driver_key: URI.encode_path(driver_key)}
          uri.query = URI::Params.encode({"api-key" => secret})

          HTTP::Client.get(uri) do |response|
            raise "failed to download driver #{driver_key}: #{response.status_code}" unless response.success?

            File.open(temp_path, mode: "w+", perm: File::Permissions.new(0o744)) do |file|
              IO.copy(response.body_io, file)
            end
          end

          # Validate the downloaded binary
          raise "invalid or corrupted binary for #{driver_key}" unless valid_binary?(temp_path)

          # Atomic move to final location
          File.rename(temp_path, path)
        end
      rescue error
        File.delete(temp_path) rescue nil
        raise error
      end

      path
    end

    def delete_binary(driver_key : String)
      path = store.path(driver_key).to_s
      File.delete(path) if File.exists?(path)
    rescue error
      Log.error(exception: error) { "failed to delete binary #{driver_key}" }
    end

    def compiled_drivers
      store.compiled_drivers.to_set
    end

    private def valid_binary?(path : String) : Bool
      return false unless File.exists?(path)
      return false unless File.size(path) > 0
      return false unless File.executable?(path)
      true
    rescue
      false
    end

    private def check_disk_space(path : String)
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      {% if flag?(:linux) || flag?(:darwin) %}
        stat = File.info(dir)
        if stat.responds_to?(:free_space) && stat.free_space < MIN_FREE_SPACE
          raise "insufficient disk space: #{stat.free_space} bytes available, need at least #{MIN_FREE_SPACE}"
        end
      {% end %}
    rescue ex : File::Error
      Log.warn(exception: ex) { "unable to check disk space for #{dir}" }
    end
  end
end
