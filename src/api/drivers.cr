require "placeos-compiler/helper"
require "redis"

require "./application"

module PlaceOS::Core::Api
  class Drivers < Application
    base "/api/core/v1/drivers/"

    # The drivers available
    @[AC::Route::GET("/")]
    def index(
      @[AC::Param::Info(description: "the repository folder name", example: "drivers")]
      repository : String
    ) : Array(String)
      Compiler::Helper.drivers(repository, Compiler.repository_dir)
    end

    # Returns the list of commits for a particular driver
    @[AC::Route::GET("/:file_name")]
    def show(
      @[AC::Param::Info(description: "the repository folder name", example: "drivers")]
      repository : String,
      @[AC::Param::Info(name: "file_name", description: "the name of the file in the repository", example: "drivers/place/meet.cr")]
      driver_file : String,
      @[AC::Param::Info(description: "the branch we want the commits from", example: "main")]
      branch : String = "master",
      @[AC::Param::Info(description: "the number of commits we want to return", example: "50")]
      count : Int32 = 50,
    ) : Array(PlaceOS::Compiler::Git::Commit)
      Compiler::Git.commits(driver_file, repository, Compiler.repository_dir, count, branch)
    end

    # Boolean check whether driver is compiled
    @[AC::Route::GET("/:file_name/compiled")]
    def compiled(
      @[AC::Param::Info(name: "file_name", description: "the name of the file in the repository", example: "drivers/place/meet.cr")]
      driver_file : String,
      commit : String,
      tag : String
    ) : Bool
      Compiler::Helper.compiled?(driver_file, commit, tag)
    end

    # Returns the details of a driver
    @[AC::Route::GET("/:file_name/details")]
    def details(
      @[AC::Param::Info(description: "the repository folder name", example: "drivers")]
      repository : String,
      @[AC::Param::Info(name: "file_name", description: "the name of the file in the repository", example: "drivers/place/meet.cr")]
      driver_file : String,
      commit : String,
    ) : Nil
      Log.context.set(driver: driver_file, repository: repository, commit: commit)

      cached = Api::Drivers.cached_details?(driver_file, repository, commit)
      unless cached.nil?
        Log.trace { "details cache hit" }

        response.headers["Content-Type"] = "application/json"
        render text: cached
      end

      Log.debug { "compiling" }

      uuid = UUID.random.to_s

      compile_result = Compiler.build_driver(
        driver_file,
        repository,
        commit,
        id: uuid
      )

      # check driver compiled
      unless compile_result.success?
        Log.error { "failed to compile" }
        # NOTE:: not using response helpers for performance
        render :internal_server_error, json: compile_result
      end

      io = IO::Memory.new
      result = Process.run(
        compile_result.path,
        {"--defaults"},
        input: Process::Redirect::Close,
        output: io,
        error: Process::Redirect::Close
      )

      execute_output = io.to_s

      # Remove the driver as it was compiled for the lifetime of the query
      File.delete(compile_result.path) if File.exists?(compile_result.path)

      unless result.success?
        Log.error { {message: "failed to execute", output: execute_output} }
        render :internal_server_error, json: {
          exit_status: result.exit_code,
          output:      execute_output,
          driver:      driver_file,
          version:     commit,
          repository:  repository,
        }
      end

      begin
        # Set the details in redis
        Api::Drivers.cache_details(driver_file, repository, commit, execute_output)
      rescue exception
        # No drama if the details aren't cached
        Log.warn(exception: exception) { "failed to cache driver details" }
      end

      # NOTE:: no need to serialise / deserialise the results, hence not using the helpers
      response.headers["Content-Type"] = "application/json"
      render text: execute_output
    end

    # Returns an array of branches for a repository
    @[AC::Route::GET("/:repository/branches")]
    def branches(
      @[AC::Param::Info(description: "the repository folder name", example: "drivers")]
      repository : String,
    ) : Array(String)
      branches = self.class.branches?(repository)
      raise Error::NotFound.new("repository not found: #{repository}") if branches.nil?
      branches
    end

    def self.branches?(folder_name : String) : Array(String)?
      path = File.expand_path(File.join(Compiler.repository_dir, folder_name))
      if Dir.exists?(path)
        Compiler::Git.repo_operation(path) do
          ExecFrom.exec_from(path, "git", {"fetch", "--all"}, environment: {"GIT_TERMINAL_PROMPT" => "0"})
          result = ExecFrom.exec_from(path, "git", {"branch", "-r"}, environment: {"GIT_TERMINAL_PROMPT" => "0"})
          if result.status.success?
            result
              .output
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

    class_getter redis : Redis { Redis.new(url: Core::REDIS_URL) }

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
