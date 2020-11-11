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
    getter body : Message::Body

    def initialize(@sequence_id, @body)
    end
  end

  alias Container = Text | Binary

  # Messages
  #############################################################################

  # Messages, grouped by producer

  module Client
    alias Request = Message::Register
    alias Response = Message::Success
  end

  module Server
    alias Request = Message::DriverLoaded | Message::DriverStatus | Message::Execute | Message::Kill | Message::Load | Message::LoadedModules | Message::ModuleLoaded | Message::RunningDrivers | Message::RunningModules | Message::Start | Message::Stop | Message::SystemStatus | Message::Unload
    alias Response = Message::RegisterResponse | Message::Success | Message::BinaryBody
  end

  alias Request = Server::Request | Client::Request
  alias Response = Server::Response | Client::Response

  module Message
    # :nodoc:
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
          json.string(to_s.underscore)
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
        getter type : Type = PlaceOS::Edge::Protocol::Message::Body::Type::{{@type.stringify.split("::").last.id}}
      {% end %}
      end
    end

    # Requests
    ###########################################################################

    # Server Requests

    struct DriverLoaded < Body
      include JSON::Serializable
      getter driver_key : String

      def initialize(@driver_key)
      end
    end

    struct DriverStatus < Body
      include JSON::Serializable
      getter driver_key : String

      def initialize(@driver_key)
      end
    end

    struct Execute < Body
      include JSON::Serializable
      getter module_id : String
      getter payload : String

      def initialize(@module_id, @payload)
      end
    end

    struct Kill < Body
      include JSON::Serializable
      getter driver_key : String

      def initialize(@driver_key)
      end
    end

    struct Load < Body
      include JSON::Serializable
      getter module_id : String
      getter driver_key : String

      def initialize(@module_id, @driver_key)
      end
    end

    struct LoadedModules < Body
      include JSON::Serializable
    end

    struct ModuleLoaded < Body
      include JSON::Serializable
      getter module_id : String

      def initialize(@module_id)
      end
    end

    struct RunningDrivers < Body
      include JSON::Serializable
    end

    struct RunningModules < Body
      include JSON::Serializable
    end

    struct Start < Body
      include JSON::Serializable
      getter module_id : String
      getter payload : String

      def initialize(@module_id, @payload)
      end
    end

    struct Stop < Body
      include JSON::Serializable
      getter module_id : String

      def initialize(@module_id)
      end
    end

    struct SystemStatus < Body
      include JSON::Serializable

      def initialize
      end
    end

    struct Unload < Body
      include JSON::Serializable
      getter module_id : String

      def initialize(@module_id)
      end
    end

    # Client Requests

    struct Register < Body
      getter modules : Array(String)
      getter drivers : Array(String)

      def initialize(@modules, @drivers)
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
    ###########################################################################

    abstract struct ResponseBody < Body
      getter success : Bool = true
    end

    struct Success < ResponseBody
      def initialize(@success : Bool)
      end
    end

    # Server Responses

    struct RegisterResponse < ResponseBody
      getter add_drivers : Array(String)
      getter remove_drivers : Array(String)
      getter add_modules : Array(Module)
      getter remove_modules : Array(Module)

      alias Module = NamedTuple(key: String, module_id: String)

      def initialize(
        @success : Bool,
        @add_drivers : Array(String) = [] of String,
        @remove_drivers : Array(String) = [] of String,
        @add_modules : Array(Module) = [] of Module,
        @remove_modules : Array(Module) = [] of Module
      )
      end
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
  end
end
