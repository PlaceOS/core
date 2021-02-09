require "./application"

module PlaceOS::Core::Api
  class Root < Application
    base "/api/core/v1/"

    getter resource_manager : ResourceManager { ResourceManager.instance }

    def index
      head :ok
    end

    get("/ready") do
      if Root.ready?
        head :ok
      else
        head :service_unavailable
      end
    end

    def self.ready?(resource_manager : ResourceManager = ResourceManager.instance)
      resource_manager.started?.tap { |ready| Log.warn { "startup has not completed" } unless ready }
    end
  end
end
