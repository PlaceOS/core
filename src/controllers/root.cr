require "./application"

module PlaceOS::Core::Api
  class Root < Application
    base "/api/core/v1/"

    getter resource_manager : ResourceManager { ResourceManager.instance }

    def index
      head :ok
    end

    get("/ready") do
      if resource_manager.started?
        head :ok
      else
        Log.warn { "startup has not completed" }
        head :service_unavailable
      end
    end
  end
end
