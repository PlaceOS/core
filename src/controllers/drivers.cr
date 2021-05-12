require "placeos-compiler/helper"
require "redis"

require "./application"

module PlaceOS::Core::Api
  class Drivers < Application
    base "/api/core/v1/drivers/"

    id_param :file_name

    # The drivers available, returns Array(String)
    def index
      repository = params["repository"]
      render json: PlaceOS::Compiler::Helper.drivers(repository)
    end

    # Returns the list of commits for a particular driver
    def show
      driver_file = URI.decode(params["file_name"])
      repository = params["repository"]
      count = (params["count"]? || 50).to_i

      render json: PlaceOS::Compiler::Helper.commits(driver_file, repository, count)
    end

    # Boolean check whether driver is compiled
    get "/:file_name/compiled", :compiled do
      driver_file = URI.decode(params["file_name"])
      commit = params["commit"]
      tag = params["tag"]

      render json: PlaceOS::Compiler::Helper.compiled?(driver_file, commit, tag)
    end

    # Returns the details of a driver
    get "/:file_name/details", :details do
      driver = URI.decode(params["file_name"])
      commit = params["commit"]
      repository = params["repository"]

      Log.context.set(driver: driver, repository: repository, commit: commit)

      cached = Api::Drivers.cached_details?(driver, repository, commit)
      unless cached.nil?
        Log.debug { "details cache hit" }

        response.headers["Content-Type"] = "application/json"
        render text: cached
      end

      Log.info { "compiling" }

      uuid = UUID.random.to_s
      compile_result = PlaceOS::Compiler::Helper.compile_driver(driver, repository, commit, id: uuid)
      temporary_driver_path = compile_result[:executable]

      # check driver compiled
      if compile_result[:exit_status] != 0
        Log.error { "failed to compile" }
        render :internal_server_error, json: compile_result
      end

      executable_path = PlaceOS::Compiler::Helper.driver_binary_path(driver, commit, uuid)
      io = IO::Memory.new
      result = Process.run(
        executable_path,
        {"--defaults"},
        input: Process::Redirect::Close,
        output: io,
        error: Process::Redirect::Close
      )

      execute_output = io.to_s

      # Remove the driver as it was compiled for the lifetime of the query
      File.delete(temporary_driver_path) if File.exists?(temporary_driver_path)

      if result.exit_code != 0
        Log.error { {message: "failed to execute", output: execute_output} }
        render :internal_server_error, json: {
          exit_status: result.exit_code,
          output:      execute_output,
          driver:      driver,
          version:     commit,
          repository:  repository,
        }
      end

      begin
        # Set the details in redis
        Api::Drivers.cache_details(driver, repository, commit, execute_output)
      rescue exception
        # No drama if the details aren't cached
        Log.warn(exception: exception) { "failed to cache driver details" }
      end

      response.headers["Content-Type"] = "application/json"
      render text: execute_output
    end

    # Returns an array of branches for a repository
    get "/:repository/branches", :branches do
      repository = params["repository"]
      branches = self.class.branches?(repository)
      head :not_found if branches.nil?

      render json: branches
    end

    def self.branches?(folder_name : String) : Array(String)?
      path = File.expand_path(File.join(Compiler.repository_dir, folder_name))
      if Dir.exists?(path)
        Compiler::GitCommands.repo_operation(path) do
          ExecFrom.exec_from(path, "git", {"fetch", "--all"}, environment: {"GIT_TERMINAL_PROMPT" => "0"})
          result = ExecFrom.exec_from(path, "git", {"branch", "-r"}, environment: {"GIT_TERMINAL_PROMPT" => "0"})
          if result[:exit_code].zero?
            result[:output]
              .to_s
              .lines
              .compact_map { |l| l.strip.lchop("origin/") unless l =~ /HEAD/ }
              .sort!
              .uniq!
          end
        end
      end
    end

    # Caching
    ###########################################################################

    class_getter redis : Redis { Redis.new(url: PlaceOS::Core::REDIS_URL) }

    # Do a look up in redis for the details
    def self.cached_details?(file_name : String, repository : String, commit : String)
      redis.get(redis_key(file_name, repository, commit))
    rescue
      nil
    end

    # Set the details in redis
    def self.cache_details(
      file_name : String,
      repository : String,
      commit : String,
      details : String,
      ttl : Time::Span = 180.days
    )
      redis.set(redis_key(file_name, repository, commit), details, ex: ttl.to_i)
    end

    def self.redis_key(file_name : String, repository : String, commit : String)
      "driver-details\\#{file_name}-#{repository}-#{commit}"
    end
  end
end
