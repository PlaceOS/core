require "./application"
require "engine-drivers/helper"

module Engine::Core
  class Drivers < Application
    base "/api/core/v1/drivers/"

    # The drivers available, returns Array(String)
    def index
      render json: EngineDrivers::Helper.drivers(params["repository"]?)
    end

    # Returns the list of commits for a particular driver
    def show
      driver = URI.decode(params["id"])
      repository = params["repository"]?
      count = (params["count"]? || 50).to_i

      render json: EngineDrivers::Helper.commits(driver, repository, count)
    end
  end
end
