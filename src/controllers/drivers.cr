require "drivers/helper"

require "./application"

module PlaceOS::Core::Api
  class Drivers < Application
    base "/api/core/v1/drivers/"

    # The drivers available, returns Array(String)
    def index
      repository = params["repository"]? || "drivers"
      render json: PlaceOS::Drivers::Helper.drivers(repository)
    end

    # Returns the list of commits for a particular driver
    def show
      driver = URI.decode(params["id"])
      repository = params["repository"]? || "drivers"
      count = (params["count"]? || 50).to_i

      render json: PlaceOS::Drivers::Helper.commits(driver, repository, count)
    end

    # Returns the details of a driver
    get "/:id/details" do
      driver = URI.decode(params["id"])
      commit = params["commit"]
      repository = params["repository"]? || "drivers"
      meta = {repository: repository, driver: driver, commit: commit}

      temporary_driver_path = nil

      if !PlaceOS::Drivers::Helper.compiled?(driver, commit)
        logger.tag_info("compiling", **meta)
        result = PlaceOS::Drivers::Helper.compile_driver(driver, repository, commit)
        # check driver compiled
        if result[:exit_status] != 0
          logger.tag_error("failed to compile", **meta)
          render :internal_server_error, json: result
        end
        temporary_driver_path = result[:executable]
      end

      executable_path = PlaceOS::Drivers::Helper.driver_binary_path(driver, commit)
      io = IO::Memory.new
      result = Process.run(
        executable_path,
        {"--defaults"},
        input: Process::Redirect::Close,
        output: io,
        error: Process::Redirect::Close
      )

      execute_output = io.to_s

      # Remove the driver if it was compiled for the lifetime of the query
      File.delete(temporary_driver_path) if temporary_driver_path && File.exists?(temporary_driver_path)

      if result.exit_code != 0
        logger.tag_error("failed to execute", **(meta.merge({output: execute_output})))
        render :internal_server_error, json: {
          exit_status: result.exit_code,
          output:      execute_output,
          driver:      driver,
          version:     commit,
          executable:  executable_path,
          repository:  repository,
        }
      end

      response.headers["Content-Type"] = "application/json"
      render text: execute_output
    end
  end
end
