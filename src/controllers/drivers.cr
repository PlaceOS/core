require "drivers/helper"
require "redis"

require "./application"

module PlaceOS::Core::Api
  class Drivers < Application
    base "/api/core/v1/drivers/"

    # The drivers available, returns Array(String)
    def index
      repository = params["repository"]
      render json: PlaceOS::Drivers::Helper.drivers(repository)
    end

    # Returns the list of commits for a particular driver
    def show
      driver = URI.decode(params["id"])
      repository = params["repository"]
      count = (params["count"]? || 50).to_i

      render json: PlaceOS::Drivers::Helper.commits(driver, repository, count)
    end

    # Returns the details of a driver
    get "/:id/details" do
      driver = URI.decode(params["id"])
      commit = params["commit"]
      repository = params["repository"]
      meta = {driver: driver, repository: repository, commit: commit}

      cached = Api::Drivers.cached_details?(driver, repository, commit)
      unless cached.nil?
        logger.tag_debug("details cache hit!", **meta)

        response.headers["Content-Type"] = "application/json"
        render text: cached
      end

      logger.tag_info("compiling", **meta)

      uuid = UUID.random.to_s
      compile_result = PlaceOS::Drivers::Helper.compile_driver(driver, repository, commit, id: uuid)
      temporary_driver_path = compile_result[:executable]

      # check driver compiled
      if compile_result[:exit_status] != 0
        logger.tag_error("failed to compile", **meta)
        render :internal_server_error, json: compile_result
      end

      executable_path = PlaceOS::Drivers::Helper.driver_binary_path(driver, commit, uuid)
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
        logger.tag_error("failed to execute", **(meta.merge({output: execute_output})))
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
      rescue
        # No drama if the details aren't cached
        logger.tag_warn("failed to cache driver details", **meta)
      end

      response.headers["Content-Type"] = "application/json"
      render text: execute_output
    end

    # Caching
    ###########################################################################

    @@redis : Redis? = nil

    def self.redis : Redis
      (@@redis ||= Redis.new(url: ENV["REDIS_URL"]?)).as(Redis)
    end

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
