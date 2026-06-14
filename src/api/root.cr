require "./application"
require "../placeos-core/healthcheck"

require "placeos-models/version"

module PlaceOS::Core::Api
  # Liveness probe target. Served as soon as the HTTP server is accepting
  # connections, before resource and module managers have loaded, and with no
  # dependency on redis, postgres or the build service — readiness is reported
  # separately by `GET /api/core/v1/ready`.
  class Liveness < ActionController::Base
    base "/"

    # responds once the server is listening, indicating the process is alive
    @[AC::Route::GET("/")]
    def alive : Nil
    end
  end

  class Root < Application
    base "/api/core/v1/"

    class_getter resource_manager : ResourceManager { ResourceManager.instance }
    class_getter module_manager : ModuleManager { ModuleManager.instance }

    # Health Check
    ###############################################################################################

    # route for checking the health of the service
    @[AC::Route::GET("/")]
    def healthcheck : Nil
      raise "healthcheck failed" unless Healthcheck.healthcheck?
    end

    # returns the build details of the service
    @[AC::Route::GET("/version")]
    def version : PlaceOS::Model::Version
      PlaceOS::Model::Version.new(
        version: VERSION,
        build_time: BUILD_TIME,
        commit: BUILD_COMMIT,
        service: APP_NAME
      )
    end

    # Readiness Check
    ###############################################################################################

    # has the service finished loading
    @[AC::Route::GET("/ready")]
    def ready : Nil
      raise Error::NotReady.new("startup has not completed") unless self.class.ready?
    end

    def self.ready?
      resource_manager.started?.tap do |ready|
        Log.warn { "startup has not completed" } unless ready
      end
    end

    class Error < Exception
      class NotReady < Error
      end
    end

    @[AC::Route::Exception(Error::NotReady, status_code: HTTP::Status::SERVICE_UNAVAILABLE)]
    def not_ready_error(_error) : Nil
    end
  end
end
