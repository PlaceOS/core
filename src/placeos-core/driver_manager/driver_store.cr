require "uri"
require "digest"
require "promise"
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

    # Per-binary fetch coordination — see `single_flight`.
    @@loading_binaries : Hash(String, Promise::DeferredPromise(Bool)) = {} of String => Promise::DeferredPromise(Bool)
    @@loading_binaries_lock : Mutex = Mutex.new

    # Counts calls out to the build service's `compiled?` endpoint — i.e. how
    # many times a fiber actually became the loader and asked for an artifact.
    # Exposed for tests so specs can assert that N concurrent first-time
    # `compiled?` calls result in exactly one fetch attempt, not N.
    @@compiled_attempts : Atomic(Int32) = Atomic(Int32).new(0)

    def self.compiled_attempts : Int32
      @@compiled_attempts.get
    end

    def self.reset_compiled_attempts : Nil
      @@compiled_attempts.set(0)
    end

    # Is there a prebuilt artifact for this driver available locally, or on the
    # build service? Downloads it when the build service has one.
    #
    # Note this only ever *asks* — it will never trigger a build. Callers that
    # need the driver to actually run want `fetch_or_build?`.
    def compiled?(file_name : String, commit : String, branch : String, uri : String) : Bool
      Log.debug { {message: "Checking whether driver is compiled or not?", driver: file_name, commit: commit, branch: branch, repo: uri} }
      path = driver_binary_path(file_name, commit)

      # Fast path — the binary is already on disk and intact.
      return true if binary_ready?(path)

      available, _ = single_flight(path) do
        # Re-check now that we hold the fetch slot: another fiber may have
        # completed a fetch between the fast-path check and us claiming it.
        binary_ready?(path) || begin
          discard_unusable_binary(path, file_name)
          download_compiled(file_name, commit, branch, uri)
        end
      end
      available
    end

    # Returns the path to a usable driver binary, asking the build service to
    # *compile* the driver when no prebuilt artifact is available.
    #
    # `compiled?` alone is not enough for anything that loads a driver on
    # demand. When the build service has never built — or has since expired —
    # an artifact for this `file_name + commit + arch`, it answers "no" and the
    # caller is stuck: nothing in that path can make the artifact appear, so
    # every subsequent attempt fails identically until something else triggers
    # a build (in practice, a restart of this service). Startup
    # (`DriverResource.load`) and the integrity checker have always fallen back
    # to compiling for exactly this reason.
    def fetch_or_build?(
      file_name : String,
      commit : String,
      branch : String,
      uri : String,
      username : String? = nil,
      password : String? = nil,
    ) : String?
      path = driver_binary_path(file_name, commit)
      return path.to_s if binary_ready?(path)

      usable, performed = single_flight(path) { obtain_or_build(path, file_name, commit, branch, uri, username, password) }

      # `compiled?` shares this coordination slot (both write the same file) but
      # gives a weaker answer: it never escalates to a build. If one of those was
      # the loader, we just inherited its "no prebuilt artifact" verdict and the
      # build we were asked for was never requested — so try again as the loader.
      # Bounded at one retry; concurrent callers collapse onto it, so it stays a
      # single build.
      unless usable || performed
        usable, _ = single_flight(path) { obtain_or_build(path, file_name, commit, branch, uri, username, password) }
      end

      usable ? path.to_s : nil
    end

    private def obtain_or_build(path : Path, file_name : String, commit : String, branch : String, uri : String, username : String?, password : String?) : Bool
      binary_ready?(path) || begin
        discard_unusable_binary(path, file_name)
        download_compiled(file_name, commit, branch, uri) ||
          request_build(path, file_name, commit, branch, uri, username, password)
      end
    end

    # Runs the block at most once per binary, sharing its outcome with every
    # concurrent caller for the same path.
    #
    # Multiple modules can share a binary (same `file_name + commit`); without
    # this each module load would see `File.exists?` as false, call out to the
    # build service, and write to the same path at the same time — corrupting
    # the file and hammering the build service for the same driver.
    #
    # While a fetch is in flight an entry exists in `@@loading_binaries` holding
    # a `Promise(Bool)`. The loader settles it with its result, or with the
    # underlying exception on failure; concurrent waiters call `promise.get` and
    # observe exactly the same outcome. The slot is *always* released and the
    # promise *always* settled before the loader returns — a slot left behind
    # holding an unsettled promise would block every future caller for that
    # binary on `promise.get` until the process restarts. Storage is bounded by
    # the number of binaries currently being fetched (typically zero).
    #
    # Returns `{result, performed}` — `performed` distinguishing "I did this
    # work" from "I rode along on someone else's", which callers need when their
    # request is stronger than the one already in flight.
    private def single_flight(path : Path, & : -> Bool) : {Bool, Bool}
      key = path.to_s

      promise, perform_fetch = @@loading_binaries_lock.synchronize do
        if existing = @@loading_binaries[key]?
          {existing, false}
        else
          prom = Promise.new(Bool)
          @@loading_binaries[key] = prom
          {prom, true}
        end
      end

      # Waiter — share the in-flight loader's outcome (returns its value or
      # re-raises its exception).
      return {promise.get, false} unless perform_fetch

      settled = false
      begin
        result = yield
        release_fetch_slot(key)
        settled = true
        promise.resolve(result)
        {result, true}
      rescue error
        release_fetch_slot(key)
        settled = true
        promise.reject(error)
        raise error
      ensure
        unless settled
          release_fetch_slot(key)
          promise.reject(Error.new("driver fetch for #{key} did not complete"))
        end
      end
    end

    private def release_fetch_slot(key : String) : Nil
      @@loading_binaries_lock.synchronize { @@loading_binaries.delete(key) }
    end

    # Is there a working binary at `path`?
    #
    # This shells out to the binary, so it must never run while holding
    # `@@loading_binaries_lock` — a slow or hung probe under the global lock
    # would stall every other driver's fetch. A partially written file from a
    # concurrent fetch simply fails the probe and is treated as missing.
    private def binary_ready?(path : Path) : Bool
      File.exists?(path) && validate_binary(path)
    end

    private def discard_unusable_binary(path : Path, file_name : String) : Nil
      return unless File.exists?(path)
      Log.warn { {message: "Local binary exists but is corrupted, removing and re-downloading", driver_file: file_name, path: path.to_s} }
      File.delete(path) rescue nil
    end

    # Ask the build service for an existing artifact and download it. Returns
    # false when it has nothing for this `file_name + commit + arch`, leaving
    # the caller to decide whether to escalate to a build.
    protected def download_compiled(file_name : String, commit : String, branch : String, uri : String) : Bool
      @@compiled_attempts.add(1)
      resp = BuildApi.compiled?(file_name, commit, branch, uri)

      unless resp.success?
        Log.warn { {message: "build service has no compiled driver for this commit", driver_file: file_name, commit: commit, branch: branch, repo: uri, status_code: resp.status_code, response: resp.body} }
        return false
      end

      begin
        fetch_binary(LinkData.from_json(resp.body))
        true
      rescue error
        Log.warn(exception: error) { {message: "failed to download compiled driver binary", driver_file: file_name, commit: commit, branch: branch, repo: uri} }
        false
      end
    end

    # No prebuilt artifact exists — ask the build service to produce one. Runs
    # inside the caller's fetch slot, so concurrent loads of the same driver
    # trigger a single build rather than one per caller.
    protected def request_build(path : Path, file_name : String, commit : String, branch : String, uri : String, username : String?, password : String?) : Bool
      Log.info { {message: "no compiled driver available, requesting a build", driver_file: file_name, commit: commit, branch: branch, repo: uri} }

      result = compile(file_name, uri, commit, branch, false, username, password)
      unless result.success
        Log.error { {message: "build service failed to compile driver", output: result.output, driver_file: file_name, commit: commit, branch: branch, repo: uri} }
        return false
      end

      # `compile` writes the artifact under the name the build service hands
      # back, which only matches `path` when the commit we asked for is the one
      # that got built (it won't be for a `HEAD` commit resolved server side).
      unless File.exists?(path)
        Log.error { {message: "build reported success but the expected binary is missing", path: path.to_s, driver_file: file_name, commit: commit} }
        return false
      end

      true
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
      result = Process.run(path.to_s, ["-h"], output: Process::Redirect::Close, error: Process::Redirect::Close)
      # If the process runs without crashing, consider it valid
      result.exit_code == 0
    rescue ex : Exception
      Log.error(exception: ex) { {message: "Driver binary validation failed", path: path.to_s} }
      false
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

    # Downloads from the artifact store share the build service's timeouts: an
    # untimed download would park the fiber holding this binary's fetch slot,
    # blocking every later load of the driver until the process restarts.
    private def with_download_client(url : URI, &)
      client = if Core.production? || url.scheme == "https"
                 ConnectProxy::HTTPClient.new(url)
               else
                 ConnectProxy::HTTPClient.new(url.host.not_nil!, 9000)
               end
      client.connect_timeout = BuildApi::CONNECT_TIMEOUT
      client.read_timeout = BuildApi::READ_TIMEOUT
      begin
        yield client
      ensure
        client.close rescue nil
      end
    end

    private def fetch_binary(link : LinkData) : String
      url = URI.parse(link.url)
      driver_file = Path[url.path].basename
      filename = Path[binary_path, driver_file]
      request_target = URI.new(path: url.path, query: url.query).to_s
      resp = with_download_client(url, &.get(request_target))
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
