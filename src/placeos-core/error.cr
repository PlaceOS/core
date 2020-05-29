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

    def initialize(@status_code : Int32, message = "")
      super(message)
    end

    def initialize(path : String, @status_code : Int32, message : String)
      super("request to #{path} failed with #{message}")
    end

    def initialize(path : String, @status_code : Int32)
      super("request to #{path} failed")
    end

    def self.from_response(path : String, response : HTTP::Client::Response)
      new(path, response.status_code, response.body)
    end
  end
end
