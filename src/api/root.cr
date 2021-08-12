require "./application"
require "../placeos-core/healthcheck"

require "placeos-models/version"

module PlaceOS::Core::Api
  class Root < Application
    base "/api/core/v1/"

    class_getter resource_manager : Resources::Manager { ResourceManager.instance }
    class_getter module_manager : Resources::Modules { Resources::Modules.instance }

    # Health Check
    ###############################################################################################

    def index
      head Healthcheck.healthcheck? ? HTTP::Status::OK : HTTP::Status::INTERNAL_SERVER_ERROR
    end

    get "/version", :version do
      render :ok, json: PlaceOS::Model::Version.new(
        version: VERSION,
        build_time: BUILD_TIME,
        commit: BUILD_COMMIT,
        service: APP_NAME
      )
    end

    # Readiness Check
    ###############################################################################################

    get("/ready") do
      head self.class.ready? ? HTTP::Status::OK : HTTP::Status::SERVICE_UNAVAILABLE
    end

    def self.ready?
      resource_manager.started?.tap do |ready|
        Log.warn { "startup has not completed" } unless ready
      end
    end
  end
end
