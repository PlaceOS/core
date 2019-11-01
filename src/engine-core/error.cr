module ACAEngine::Core
  class Error < Exception
    getter message

    def initialize(@message : String = "")
      super(@message)
    end
  end

  class ModuleError < Error
  end

  class ClientError < Error
    def initialize(@status_code : Int32, message = "")
      super(message)
    end

    def self.from_response(response : HTTP::Client::Response)
      new(response.status_code, response.body)
    end
  end
end
