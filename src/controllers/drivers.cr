require "engine-drivers/helper"

require "./application"

module ACAEngine::Core::Api
  class Drivers < Application
    base "/api/core/v1/drivers/"

    # The drivers available, returns Array(String)
    def index
      repository = params["repository"]? || "drivers"
      render json: ACAEngine::Drivers::Helper.drivers(repository)
    end

    # Returns the list of commits for a particular driver
    def show
      driver = URI.decode(params["id"])
      repository = params["repository"]? || "drivers"
      count = (params["count"]? || 50).to_i

      render json: ACAEngine::Drivers::Helper.commits(driver, repository, count)
    end

    # Returns the details of a driver
    get "/:id/details" do
      driver = URI.decode(params["id"])
      commit = params["commit"]
      repository = params["repository"]? || "drivers"

      if !ACAEngine::Drivers::Helper.compiled?(driver, commit)
        logger.info "compiling #{repository}/#{driver}@#{commit}"
        result = ACAEngine::Drivers::Helper.compile_driver(driver, repository, commit)
        # check driver compiled
        if result[:exit_status] != 0
          logger.error "failed to compile #{repository}/#{driver}@#{commit}"
          render :internal_server_error, json: result
        end
      end

      exe_path = ACAEngine::Drivers::Helper.driver_binary_path(driver, commit)
      io = IO::Memory.new
      result = Process.run(
        exe_path,
        {"--defaults"},
        input: Process::Redirect::Close,
        output: io,
        error: Process::Redirect::Close
      )

      if result.exit_status != 0
        logger.error "failed to execute #{repository}/#{driver}@#{commit}"
        render :internal_server_error, json: {
          exit_status: result.exit_status,
          output:      io.to_s,
          driver:      driver,
          version:     commit,
          executable:  exe_path,
          repository:  repository,
        }
      end

      response.headers["Content-Type"] = "application/json"
      render text: io.to_s
    end
  end
end
