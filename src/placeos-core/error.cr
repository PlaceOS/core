module PlaceOS::Core
  class Error < Exception
    getter message

    def initialize(@message : String = "")
      super(@message)
    end
  end

  class ModuleError < Error
  end

  class ClientError < Error
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

    def initialize(@status_code : Int32, message = "")
      super(message)
    end

    def initialize(path : String, @status_code : Int32, message : String)
      super("request to #{path} failed with #{message}")
    end

    def initialize(path : String, @status_code : Int32)
      super("request to #{path} failed")
    end

    def initialize(
      error_code : ErrorCode,
      @status_code : Int32,
      message : String = "",
      @remote_backtrace : Array(String)? = nil
    )
      super(message)
    end

    def self.from_response(path : String, response : HTTP::Client::Response)
      new(path, response.status_code, response.body)
    end
  end
end
