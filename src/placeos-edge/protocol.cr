require "bindata"
require "json"
require "placeos-driver/protocol/management"

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
  module Message
    # :nodoc:
    abstract struct Body
      include JSON::Serializable

      # TODO:
      # - Refactor to indivual enums for better case exhaustiveness
      # - Maybe make a macro that casts a Body based on type

      enum Type
        # Request

        # -> Server
        DriverLoaded # Success
        DriverStatus
        Execute
        Kill # Success
        Load # Success
        LoadedModules
        ModuleLoaded # Success
        RunCount
        Start # Success
        Stop  # Success
        SystemStatus
        Unload # Success

        # -> Client
        Register
        ProxyRedis # Success
        FetchBinary
        SettingsAction # Success

        # Response
        Success

        # -> Server
        RegisterResponse

        # -> Client
        DriverStatusResponse
        ExecuteResponse
        LoadedModulesResponse
        RunCountResponse
        SystemStatusResponse

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

    abstract struct ::PlaceOS::Edge::Protocol::Server::Request < ::PlaceOS::Edge::Protocol::Message::Body
    end

    abstract struct ::PlaceOS::Edge::Protocol::Client::Request < ::PlaceOS::Edge::Protocol::Message::Body
    end

    # Requests
    ###############################################################################################

    # Server Requests
    ###########################################################################

    struct DriverLoaded < Server::Request
      getter driver_key : String

      def initialize(@driver_key)
      end
    end

    struct DriverStatus < Server::Request
      getter driver_key : String

      def initialize(@driver_key)
      end
    end

    struct Execute < Server::Request
      getter module_id : String
      getter payload : String

      def initialize(@module_id, @payload)
      end
    end

    struct Kill < Server::Request
      getter driver_key : String

      def initialize(@driver_key)
      end
    end

    struct Load < Server::Request
      getter module_id : String
      getter driver_key : String

      def initialize(@module_id, @driver_key)
      end
    end

    struct RunCount < Server::Request
      getter modules : Int32
      getter drivers : Int32

      def initialize(@modules, @drivers)
      end
    end

    struct LoadedModules < Server::Request
    end

    struct ModuleLoaded < Server::Request
      getter module_id : String

      def initialize(@module_id)
      end
    end

    struct Start < Server::Request
      getter module_id : String
      getter payload : String

      def initialize(@module_id, @payload)
      end
    end

    struct Stop < Server::Request
      getter module_id : String

      def initialize(@module_id)
      end
    end

    struct SystemStatus < Server::Request
      def initialize
      end
    end

    struct Unload < Server::Request
      getter module_id : String

      def initialize(@module_id)
      end
    end

    # Client Requests
    ###########################################################################

    struct FetchBinary < Client::Request
      getter key : String

      def initialize(@key)
      end
    end

    struct Register < Client::Request
      getter modules : Array(String)
      getter drivers : Array(String)

      def initialize(@modules, @drivers)
      end
    end

    struct ProxyRedis < Client::Request
      getter action : RedisAction
      getter hash_id : String
      getter key_name : String
      getter status_value : String?

      def initialize(
        @action,
        @hash_id,
        @key_name,
        @status_value
      )
      end
    end

    struct SettingsAction < Client::Request
      getter module_id : String
      getter setting_name : String
      getter setting_value : YAML::Any

      def initialize(@module_id, @setting_name, @setting_value)
      end
    end

    # Responses
    ###############################################################################################

    abstract struct ResponseBody < ::PlaceOS::Edge::Protocol::Message::Body
      getter success : Bool = true
    end

    abstract struct ::PlaceOS::Edge::Protocol::Client::Response < ::PlaceOS::Edge::Protocol::Message::ResponseBody
    end

    abstract struct ::PlaceOS::Edge::Protocol::Server::Response < ::PlaceOS::Edge::Protocol::Message::ResponseBody
    end

    struct Success < ResponseBody
      def initialize(@success : Bool)
      end
    end

    # Client Responses
    ############################################################################

    struct DriverStatusResponse < Client::Response
      getter status : Core::ProcessManager::DriverStatus?

      def initialize(@status : Core::ProcessManager::DriverStatus?)
      end
    end

    struct ExecuteResponse < Client::Response
      getter output : String?

      def initialize(@output : String?)
      end
    end

    struct LoadedModulesResponse < Client::Response
      getter modules : Hash(String, Array(String))

      def initialize(@modules : Hash(String, Array(String)))
      end
    end

    struct RunCountResponse < Client::Response
      getter drivers : Int32
      getter modules : Int32

      def initialize(@drivers : Int32, @modules : Int32)
      end
    end

    struct SystemStatusResponse < Client::Response
      getter status : Core::ProcessManager::SystemStatus

      def initialize(@status : Core::ProcessManager::SystemStatus)
      end
    end

    # Server Responses
    ############################################################################

    # Binary response constructor
    class BinaryBody
      getter key : String
      getter binary : Bytes
      getter success : Bool = true

      def initialize(@key, @binary)
      end
    end

    struct RegisterResponse < Server::Response
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
  end

  alias RedisAction = ::PlaceOS::Driver::Protocol::Management::RedisAction

  private macro unwrap_subclasses(to_alias, type_union)
    alias {{ to_alias }} = Union(
      {% for klass in type_union.resolve.union_types %}
        {% unless klass.abstract? || !klass.subclasses.empty? %}
          {{ klass }},
        {% end %}
        {% for generic in klass.subclasses %}
          {% for sub in generic.subclasses %}
            {{ sub }},
          {% end %}
        {% end %}
      {% end %}
    )
  end

  {% begin %}
    unwrap_subclasses(Request, Union(Server::Request, Client::Request))
    unwrap_subclasses(Response, Union(Server::Response, Client::Response, Message::Success, Message::BinaryBody))
  {% end %}
end
