require "uuid"
require "action-controller"

module ACAEngine::Core::Api
  abstract class Application < ActionController::Base
    before_action :set_request_id

    # This makes it simple to match client requests with server side logs.
    # When building microservices this ID should be propagated to upstream services.
    def set_request_id
      response.headers["X-Request-ID"] = logger.request_id = request.headers["X-Request-ID"]? || UUID.random.to_s
    end
  end
end
