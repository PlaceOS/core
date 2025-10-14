require "uri"
require "digest"
require "connect-proxy"
require "./build_api"

module PlaceOS::Core
  record Result, success : Bool = false, output : String = "", name : String = "", path : String = ""

  class DriverStore
    BINARY_PATH = ENV["PLACEOS_DRIVER_BINARIES"]?.presence || Path["./bin/drivers"].expand.to_s

    protected getter binary_path : String

    def initialize(@binary_path : String = BINARY_PATH)
      Dir.mkdir_p binary_path
    end

    def compiled?(file_name : String, commit : String, branch : String, uri : String) : Bool
      Log.debug { {message: "Checking whether driver is compiled or not?", driver: file_name, commit: commit, branch: branch, repo: uri} }
      path = Path[binary_path, executable_name(file_name, commit)]

      if File.exists?(path)
        # Validate that the local file is a valid executable by running it with -h
        if validate_binary(path)
          return true
        else
          Log.warn { {message: "Local binary exists but is corrupted, removing and re-downloading", driver_file: file_name, path: path.to_s} }
          File.delete(path) rescue nil
        end
      end

      resp = BuildApi.compiled?(file_name, commit, branch, uri)
      return false unless resp.success?
      ret = fetch_binary(LinkData.from_json(resp.body)) rescue nil
      !ret.nil?
    end

    def compile(file_name : String, url : String, commit : String, branch : String, force : Bool, username : String? = nil, password : String? = nil, fetch : Bool = true) : Result
      Log.info { {message: "Requesting build service to compile driver", driver_file: file_name, branch: branch, repository: url} }
      begin
        resp = BuildApi.compile(file_name, url, commit, branch, force, username, password)
        unless fetch
          return Result.new(success: true)
        end
        resp = resp.not_nil!
        unless resp.success?
          Log.error { {message: resp.body, status_code: resp.status_code, driver: file_name, commit: commit, branch: branch, force: force} }
          return Result.new(output: resp.body, name: file_name)
        end
        link = LinkData.from_json(resp.body)
        begin
          driver = fetch_binary(link)
        rescue ex
          return Result.new(output: ex.message.not_nil!, name: file_name)
        end
        Result.new(success: true, name: driver, path: binary_path)
      rescue ex
        msg = ex.message || "compiled returned no exception message"
        Log.error(exception: ex) { {message: msg, driver: file_name, commit: commit, branch: branch, force: force} }
        Result.new(output: msg, name: file_name)
      end
    end

    def metadata(file_name : String, commit : String, branch : String, uri : String)
      resp = BuildApi.metadata(file_name, commit, branch, uri)
      return Result.new(success: true, output: resp.body.as(String)) if resp.success?
      Result.new(output: "Metadata not found. Server returned #{resp.status_code}")
    rescue ex
      Result.new(output: ex.message.not_nil!, name: file_name)
    end

    def defaults(file_name : String, commit : String, branch : String, uri : String)
      resp = BuildApi.defaults(file_name, commit, branch, uri)
      return Result.new(success: true, output: resp.body.as(String)) if resp.success?
      Result.new(output: "Driver defaults not found. Server returned #{resp.status_code}")
    rescue ex
      Result.new(output: ex.message.not_nil!, name: file_name)
    end

    def built?(file_name : String, commit : String, branch : String, uri : String) : String?
      return nil unless compiled?(file_name, commit, branch, uri)
      driver_binary_path(file_name, commit).to_s
    end

    def driver_binary_path(file_name : String, commit : String)
      Path[binary_path, executable_name(file_name, commit)]
    end

    def path(driver_file : String) : Path
      Path[binary_path, driver_file]
    end

    def compiled_drivers : Array(String)
      Dir.children(binary_path)
    end

    def executable_name(driver_source, commit)
      driver_source = driver_source.rchop(".cr").gsub(/\/|\./, "_")
      commit = commit[..6] if commit.size > 6
      {driver_source, commit, Core::ARCH}.join("_").downcase
    end

    private def validate_binary(path : Path) : Bool
      # Try to execute the binary with -h flag to validate it's a working executable
      begin
        result = Process.run(path.to_s, ["-h"], output: Process::Redirect::Close, error: Process::Redirect::Close)
        # If the process runs without crashing, consider it valid
        result.exit_code == 0
      rescue ex : Exception
        Log.error(exception: ex) { {message: "Driver binary validation failed", path: path.to_s} }
        false
      end
    end

    def reload_driver(driver_id : String)
      if driver = Model::Driver.find?(driver_id)
        repo = driver.repository!

        if compiled?(driver.file_name, driver.commit, repo.branch, repo.uri)
          manager = ModuleManager.instance
          stale_path = manager.reload_modules(driver)
          if path = stale_path
            File.delete(path) rescue nil if File.exists?(path)
          end
        else
          return {status: 404, message: "Driver not compiled or not available on S3"}
        end
      else
        return {status: 404, message: "Driver with id #{driver_id} not found "}
      end
      {status: 200, message: "OK"}
    end

    private def fetch_binary(link : LinkData) : String
      url = URI.parse(link.url)
      driver_file = Path[url.path].basename
      filename = Path[binary_path, driver_file]
      resp = if Core.production? || url.scheme == "https"
               ConnectProxy::HTTPClient.get(url.to_s)
             else
               uri = URI.new(path: url.path, query: url.query)
               ConnectProxy::HTTPClient.new(url.host.not_nil!, 9000).get(uri.to_s)
             end
      if resp.success?
        # Check Content-Length header first if available
        content_length = resp.headers.fetch("Content-Length", "0").to_i64
        if content_length > 0 && link.size != content_length
          Log.error { {message: "Expected content length #{link.size}, but received #{content_length}", driver_file: driver_file} }
          raise Error.new("Response size doesn't match with build service returned result")
        end

        body_io = IO::Digest.new(resp.body_io? || IO::Memory.new(resp.body), Digest::MD5.new)
        bytes_written = 0_i64
        File.open(filename, "wb+") do |f|
          bytes_written = IO.copy(body_io, f)
          f.chmod(0o755)
        end

        # Verify actual downloaded size matches expected size
        unless link.size == bytes_written
          Log.error { {message: "Expected download size #{link.size}, but actually downloaded #{bytes_written} bytes", driver_file: driver_file} }
          File.delete(filename) if File.exists?(filename)
          raise Error.new("Downloaded size doesn't match expected size from build service")
        end

        filename.to_s
      else
        raise Error.new("Unable to fetch driver. Error : #{resp.body}")
      end
    end

    private record LinkData, size : Int64, md5 : String, modified : Time, url : String, link_expiry : Time do
      include JSON::Serializable
      @[JSON::Field(converter: Time::EpochConverter)]
      getter modified : Time
      @[JSON::Field(converter: Time::EpochConverter)]
      getter link_expiry : Time
    end

    enum State
      Pending
      Running
      Cancelled
      Error
      Done

      def to_s(io : IO) : Nil
        io << (member_name || value.to_s).downcase
      end

      def to_s : String
        String.build { |io| to_s(io) }
      end
    end

    record TaskStatus, state : State, id : String, message : String,
      driver : String, repo : String, branch : String, commit : String, timestamp : Time do
      include JSON::Serializable
    end

    record CancelStatus, status : String, message : String do
      include JSON::Serializable
    end

    def monitor_jobs(state : State = State::Pending)
      resp = BuildApi.monitor(state.to_s)
      return {success: true, output: Array(TaskStatus).from_json(resp.body), code: 200} if resp.success?
      {success: false, output: "Build service returned #{resp.status_code} with reponse #{resp.body}", code: resp.status_code}
    rescue ex
      {success: false, output: "Call to Build service endpoint failed with error  #{ex.message}", code: 500}
    end

    def cancel_job(job : String)
      resp = BuildApi.cancel_job(job)

      return {success: true, output: CancelStatus.from_json(resp.body), code: resp.status_code} if resp.success? || resp.status_code == 409
      {success: false, output: CancelStatus.new("error", "Build service returned #{resp.status_code} with reponse #{resp.body}"), code: resp.status_code}
    rescue ex
      {success: false, output: CancelStatus.new("error", "Call to Build service endpoint failed with error  #{ex.message}"), code: 500}
    end
  end
end
