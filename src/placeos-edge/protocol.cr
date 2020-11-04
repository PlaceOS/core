require "bindata"
require "json"

require "./record"

module PlaceOS::Edge::Protocol
  # Containers
  #############################################################################

  # Binary messages
  #
  class Binary < BinData
    endian big
    uint64 :sequence_id

    int32 :size, value: ->{ key.bytesize }
    string :key, length: ->{ size }

    remaining_bytes :body
  end

  # Text messages
  #
  class Text
    include JSON::Serializable
    include JSON::Serializable::Strict

    getter sequence_id : UInt64
    getter body : Body

    def initialize(@sequence_id, @body)
    end
  end

  alias Container = Text | Binary

  # Messages
  #############################################################################

  abstract def debug(module_id : String, &on_message : String ->)
  abstract def ignore(module_id : String, &on_message : String ->)

  abstract struct Body
    include JSON::Serializable

    enum Type
      # Request

      # -> Server
      DriverLoaded
      DriverStatus
      Execute
      Kill # Success
      Load # Success
      LoadedModules
      ModuleLoaded
      RunningDrivers
      RunningModules
      Start # Success
      Stop  # Success
      SystemStatus
      Unload # Success

      # -> Client
      Register
      WriteRedis # Success
      FetchBinary

      # Response
      Success

      # -> Server
      RegisterResponse

      # -> Client

      def to_json(json : JSON::Builder)
        json.string(to_s.downcase)
      end
    end

    {% begin %}
    use_json_discriminator "type", {
    {% for response in Type.constants.map { |t| ({t.underscore, t}) } %}
      {{ response[0] }} => {{ response[1].id }},
    {% end %}
    }
    {% end %}

    macro inherited
      {% unless @type.abstract? %}
        getter type : Type = PlaceOS::Edge::Protocol::Body::Type::{{@type.stringify.split("::").last.id}}
      {% end %}
    end
  end

  # Requests

  struct Execute < Body
    getter module_id : String
    getter payload : String

    def initialize(@module_id, @payload)
    end
  end

  struct Register < Body
    def initialize
    end
  end

  struct WriteRedis < Body
    getter module_id : String
    getter key : String
    getter value : String

    def initialize(@module_id, @key, @value)
    end
  end

  struct FetchBinary < Body
    getter key : String

    def initialize(@key)
    end
  end

  # Responses

  abstract struct ResponseBody < Body
    getter success : Bool = true
  end

  struct Success < ResponseBody
    def initialize(@success : Bool)
    end
  end

  struct RegisterResponse < ResponseBody
    getter add_drivers : Array(String)
    getter remove_drivers : Array(String)
    getter add_modules : Array(String)
    getter remove_modules : Array(String)

    def initialize(
      @success : Bool,
      @add_drivers : Array(String) = [] of String,
      @remove_drivers : Array(String) = [] of String,
      @add_modules : Array(String) = [] of String,
      @remove_modules : Array(String) = [] of String
    )
    end
  end

  struct Load < Body
    getter module_id : String
    getter driver_key : String

    def initialize(@module_id, @driver_key)
    end
  end

  struct Unload < Body
    getter module_id : String

    def initialize(@module_id)
    end
  end

  struct Start < Body
    getter module_id : String
    getter payload : String

    def initialize(@module_id, @payload)
    end
  end

  struct Stop < Body
    getter module_id : String

    def initialize(@module_id)
    end
  end

  struct Kill < Body
    getter driver_key : String

    def initialize(@driver_key)
    end
  end

  struct DriverStatus < Body
    getter driver_key : String

    def initialize(@driver_key)
    end
  end

  struct SystemStatus < Body
    def initialize
    end
  end

  struct ModuleLoaded < Body
    getter module_id : String

    def initialize(@module_id)
    end
  end

  struct DriverLoaded < Body
    getter driver_key : String

    def initialize(@driver_key)
    end
  end

  struct RunningDrivers < Body
  end

  struct RunningModules < Body
  end

  struct LoadedModules < Body
  end

  # Binary Response
  #
  class BinaryBody
    getter key : String
    getter binary : Bytes
    getter success : Bool = true

    def initialize(@key, @binary)
    end
  end

  # Messages, grouped by producer

  module Client
    alias Request = Register
    alias Response = ResponseBody
  end

  module Server
    alias Request = LoadedModules | Execute
    alias Response = ResponseBody | BinaryBody
  end

  alias Request = Server::Request | Client::Request
  alias Response = Server::Response | Client::Response
  alias Message = Request | Response
end
