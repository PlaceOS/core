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
  end
end
