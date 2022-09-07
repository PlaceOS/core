require "uuid"
require "action-controller"

module PlaceOS::Core::Api
  abstract class Application < ActionController::Base
    Log = ::PlaceOS::Core::Log.for("controller")

    getter request_id : String do
      request.headers["X-Request-ID"]? || UUID.random.to_s
    end

    # This makes it simple to match client requests with server side logs.
    # When building microservices this ID should be propagated to upstream services.
    @[AC::Route::Filter(:before_action)]
    protected def configure_request_logging
      Log.context.set(
        client_ip: client_ip,
        request_id: request_id,
      )
      response.headers["X-Request-ID"] = request_id
    end

    # =====================
    # Error Handling
    # =====================

    class Error < Exception
      class NotFound < Error
      end

      class NotAcceptable < Error
      end
    end

    struct CommonError
      include JSON::Serializable

      getter error : String?
      getter backtrace : Array(String)?

      def initialize(error)
        @error = error.message
        @backtrace = error.backtrace
      end
    end

    # handler for common errors
    @[AC::Route::Exception(Error::NotFound, status_code: HTTP::Status::NOT_FOUND)]
    @[AC::Route::Exception(Error::NotAcceptable, status_code: HTTP::Status::NOT_ACCEPTABLE)]
    def common_error(error) : CommonError
      Log.debug { error.message }
      CommonError.new(error)
    end

    # Provides details on available data formats
    struct ContentError
      include JSON::Serializable
      include YAML::Serializable

      getter error : String
      getter accepts : Array(String)? = nil

      def initialize(@error, @accepts = nil)
      end
    end

    # covers no acceptable response format and not an acceptable post format
    @[AC::Route::Exception(AC::Route::NotAcceptable, status_code: HTTP::Status::NOT_ACCEPTABLE)]
    @[AC::Route::Exception(AC::Route::UnsupportedMediaType, status_code: HTTP::Status::UNSUPPORTED_MEDIA_TYPE)]
    def bad_media_type(error) : ContentError
      ContentError.new error: error.message.not_nil!, accepts: error.accepts
    end

    # Provides details on which parameter is missing or invalid
    struct ParameterError
      include JSON::Serializable
      include YAML::Serializable

      getter error : String
      getter parameter : String? = nil
      getter restriction : String? = nil

      def initialize(@error, @parameter = nil, @restriction = nil)
      end
    end

    # handles paramater missing or a bad paramater value / format
    @[AC::Route::Exception(AC::Route::Param::MissingError, status_code: HTTP::Status::UNPROCESSABLE_ENTITY)]
    @[AC::Route::Exception(AC::Route::Param::ValueError, status_code: HTTP::Status::BAD_REQUEST)]
    def invalid_param(error) : ParameterError
      ParameterError.new error: error.message.not_nil!, parameter: error.parameter, restriction: error.restriction
    end
  end
end
