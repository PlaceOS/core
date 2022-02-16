module PlaceOS::Core
  class Error < Exception
    getter message

    def initialize(@message : String = "", @cause = nil)
      super
    end
  end

  class ModuleError < Error
  end

  class ClientError < Error
    getter code : Int32
    getter status_code
    getter remote_backtrace

    enum ErrorCode
      # The request was sent and error occured in core / the module
      RequestFailed = 0
      # Some other transient failure like database unavailable
      UnexpectedFailure = 1

      def to_s
        super.underscore
      end
    end

    def initialize(@status_code : Int32, message = "", @code = 500)
      super(message)
    end

    def initialize(path : String, @status_code : Int32, message : String, @code = 500)
      super("request to #{path} failed with #{message}")
    end

    def initialize(path : String, @status_code : Int32, @code = 500)
      super("request to #{path} failed")
    end

    def initialize(
      error_code : ErrorCode,
      @status_code : Int32,
      message : String = "",
      @remote_backtrace : Array(String)? = nil,
      code : Int32? = 500
    )
      @code = code || 500
      super(message)
    end

    def self.from_response(path : String, response : HTTP::Client::Response)
      new(path, response.status_code, response.body)
    end
  end
end
