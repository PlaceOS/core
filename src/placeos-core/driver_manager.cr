require "uri"
require "digest"
require "connect-proxy"
require "placeos-models"
require "placeos-resource"
require "./module_manager"

module PlaceOS::Core
  class DriverStore
    BINARY_PATH = ENV["PLACEOS_DRIVER_BINARIES"]?.presence || Path["./bin/drivers"].expand.to_s

    protected getter binary_path : String

    def initialize(@binary_path : String = BINARY_PATH)
      Dir.mkdir_p binary_path
    end

    def compiled?(file_name : String, commit : String, branch : String) : Bool
      path = Path[binary_path, executable_name(file_name, commit)]
      return true if File.exists?(path)
      resp = BuildApi.compiled?(file_name, commit, branch)
      return false unless resp.success?
      ret = fetch_binary(LinkData.from_json(resp.body)) rescue nil
      !ret.nil?
    end

    def compile(file_name : String, url : String, commit : String, branch : String, force : Bool, username : String? = nil, password : String? = nil) : Result
      Log.info { {message: "Requesting build service to compile driver", driver_file: file_name, branch: branch, repository: url} }
      begin
        resp = BuildApi.compile(file_name, url, commit, branch, force)
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

    def built?(file_name : String, commit : String, branch : String) : String?
      return nil unless compiled?(file_name, commit, branch)
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

    private def fetch_binary(link : LinkData) : String
      url = URI.parse(link.url)
      driver_file = Path[url.path].basename
      filename = Path[binary_path, driver_file]
      resp = if Core.production?
               ConnectProxy::HTTPClient.get(url.to_s)
             else
               uri = URI.new(path: url.path, query: url.query)
               ConnectProxy::HTTPClient.new(url.host.not_nil!, 9000).get(uri.to_s)
             end
      if resp.success?
        unless link.size == resp.headers.fetch("Content-Length", "0").to_i
          Log.error { {message: "Expected content length #{link.size}, but received #{resp.headers.fetch("Content-Length", "0")}", driver_file: driver_file} }
          raise Error.new("Response size doesn't match with build service returned result")
        end
        body_io = IO::Digest.new(IO::Memory.new(resp.body), Digest::MD5.new)
        File.open(filename, "wb") do |f|
          IO.copy(body_io, f)
          f.chmod(0o755)
        end
        md5 = body_io.final.hexstring
        unless link.md5 == md5
          Log.error { {message: "Invalid checksum md5 of received file. Removing driver file", driver_file: driver_file} }
          File.delete(filename) rescue nil
          raise Error.new("Retrieved driver checksum md5 doesn't match with build service returned result")
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
  end

  module BuildApi
    BUILD_API_BASE = "/api/build/v1"

    def self.compiled?(file_name : String, commit : String, branch : String)
      host = URI.parse(Core.build_host)
      file_name = URI.encode_www_form(file_name)
      ConnectProxy::HTTPClient.new(host) do |client|
        path = "#{BUILD_API_BASE}/#{Core::ARCH}/compiled/#{file_name}"
        params = URI::Params.encode({"branch" => branch, "commit" => commit})
        uri = "#{path}?#{params}"
        client.get(uri)
      end
    end

    def self.compile(file_name : String, url : String, commit : String, branch : String, force : Bool, username : String? = nil, password : String? = nil)
      host = URI.parse(Core.build_host)
      file_name = URI.encode_www_form(file_name)
      headers = HTTP::Headers.new
      headers["X-Git-Username"] = username.not_nil! unless username.nil?
      headers["X-Git-Password"] = password.not_nil! unless password.nil?

      resp = ConnectProxy::HTTPClient.new(host) do |client|
        path = "#{BUILD_API_BASE}/#{Core::ARCH}/#{file_name}"
        params = URI::Params.encode({"url" => url, "branch" => branch, "commit" => commit, "force" => force.to_s})
        uri = "#{path}?#{params}"
        client.post(uri, headers: headers)
      end

      raise "Build API returned #{resp.status_code} while 202 was expected. Returned error: #{resp.body}" unless resp.status_code == 202
      link = resp.headers["Content-Location"] rescue raise "Build API returned invalid response, missing Content-Location header"

      task = JSON.parse(resp.body).as_h
      loop do
        resp = ConnectProxy::HTTPClient.new(host) do |client|
          client.get(link)
        end
        raise "Returned invalid response : #{link}" unless resp.success?
        task = JSON.parse(resp.body).as_h
        break if task["state"] != "pending"
        sleep 5
      end
      if resp.success? && task["state"] == "error"
        raise task["message"].to_s
      end
      raise "Build API end-point #{link} returned invalid response code #{resp.status_code}, expected 303" unless resp.status_code == 303
      raise "Build API end-point #{link} returned invalid state #{task["state"]}, expected 'done'" unless task["state"] == "done"
      hdr = resp.headers["Location"] rescue raise "Build API returned compilation done, but missing Location URL"
      ConnectProxy::HTTPClient.new(host) do |client|
        client.get(hdr)
      end
    end
  end

  record Result, success : Bool = false, output : String = "", name : String = "", path : String = ""

  class DriverResource < Resource(Model::Driver)
    private getter? startup : Bool = true
    private getter module_manager : ModuleManager
    private getter store : DriverStore
    private getter lock : Mutex = Mutex.new

    def initialize(
      @startup : Bool = true,
      @binary_dir : String = "#{Dir.current}/bin/drivers",
      @module_manager : ModuleManager = ModuleManager.instance
    )
      @store = DriverStore.new
      buffer_size = System.cpu_count.to_i
      super(buffer_size)
    end

    def process_resource(action : Resource::Action, resource driver : Model::Driver) : Resource::Result
      case action
      in .created?, .updated?
        result = DriverResource.load(driver, store, startup?, module_manager)
        unless result.success
          if driver.compilation_output.nil? || driver.recompile_commit? || driver.commit_changed?
            driver.update_fields(compilation_output: result.output)
          end
          raise Resource::ProcessingError.new(driver.name, result.output)
        end

        driver.update_fields(compilation_output: nil) unless driver.compilation_output.nil?
        Resource::Result::Success
      in .deleted?
        Result::Skipped
      end
    rescue exception
      raise Resource::ProcessingError.new(driver.name, "#{exception} #{exception.message}", cause: exception)
    end

    def self.load(
      driver : Model::Driver,
      store : DriverStore,
      startup : Bool = false,
      module_manager : ModuleManager = ModuleManager.instance
    ) : Core::Result
      driver_id = driver.id.as(String)
      repository = driver.repository!

      force_recompile = driver.recompile_commit?
      commit = force_recompile.nil? ? driver.commit : force_recompile

      ::Log.with_context(
        driver_id: driver_id,
        name: driver.name,
        file_name: driver.file_name,
        repository_name: repository.folder_name,
        commit: commit,
      ) do
        if !force_recompile && !driver.commit_changed? && (path = store.built?(driver.file_name, commit, repository.branch))
          Log.info { "commit unchanged and driver already compiled" }
          module_manager.reload_modules(driver)
          return Core::Result.new(success: true, path: path)
        end

        Log.info { "force recompiling driver" } if force_recompile
      end

      # If the commit is `head` then the driver must be recompiled at the latest version
      force = !force_recompile.nil? || commit.try(&.upcase) == "HEAD"

      result = store.compile(
        driver.file_name,
        repository.uri,
        commit,
        repository.branch,
        force,
        repository.username,
        repository.decrypt_password
      )

      unless result.success
        Log.error { {message: "failed to compile driver", output: result.output, repository_name: repository.folder_name} }
        return Core::Result.new(output: "failed to compile #{driver.name} from #{repository.folder_name}: #{result.output}")
      end

      Log.info { {
        message:         "compiled driver",
        name:            driver.name,
        executable:      result.name,
        repository_name: repository.folder_name,
        output:          result.output,
      } }

      # (Re)load modules onto the newly compiled driver
      stale_path = module_manager.reload_modules(driver)

      # Remove the stale driver if there was one
      remove_stale_driver(driver_id: driver_id,
        path: stale_path,
      )

      # Bump the commit on the driver post-compilation and module loading
      if (force) && (startup || module_manager.discovery.own_node?(driver_id))
        update_driver_commit(driver: driver, commit: commit, startup: startup)
      end

      result
    end

    # Remove the stale driver binary if there was one
    #
    def self.remove_stale_driver(path : Path?, driver_id : String)
      return unless path
      Log.info { {message: "removing stale driver binary", driver_id: driver_id, path: path.to_s} }
      File.delete(path) if File.exists?(path)
    rescue
      Log.error { {message: "failed to remove stale binary", driver_id: driver_id, path: path.to_s} }
    end

    def self.update_driver_commit(driver : Model::Driver, commit : String, startup : Bool)
      if startup
        # There's a potential for multiple writers on startup, However this is an eventually consistent operation.
        Log.warn { {message: "updating commit on driver during startup", id: driver.id, name: driver.name, commit: commit} }
      end

      driver.update_fields(commit: commit)
      Log.info { {message: "updated commit on driver", id: driver.id, name: driver.name, commit: commit} }
    end

    def start
      super
      @startup = false
      self
    end
  end
end
