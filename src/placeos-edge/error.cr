require "./protocol"

module PlaceOS::Edge
  class Error < Exception
    getter message

    def initialize(@message : String = "")
      super(@message)
    end

    class TransportTimeout < Error
      getter request

      def initialize(@request : Protocol::Request)
        super("sending #{@request.type} timed out")
      end
    end
  end
end
