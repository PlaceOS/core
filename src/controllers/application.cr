require "uuid"
require "action-controller"

module PlaceOS::Core::Api
  abstract class Application < ActionController::Base
    Log = ::App::Log.for("controller")
  
    before_action :set_request_id

    # This makes it simple to match client requests with server side logs.
    # When building microservices this ID should be propagated to upstream services.
    def set_request_id
      request_id = request.headers["X-Request-ID"]? || UUID.random.to_s
      Log.context.set(
        client_ip: client_ip,
        request_id: request_id
      )
      response.headers["X-Request-ID"] = request_id
    end
  end
end
