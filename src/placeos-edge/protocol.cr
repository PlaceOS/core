require "bindata"
require "json"

require "placeos-driver/protocol/management"

require "../placeos-core/process_manager"

module PlaceOS::Edge::Protocol
  # Containers
  #############################################################################

  # Binary messages
  #
  class Binary < BinData
    enum Status
      Success
      Fail
    end

    endian big
    uint64 :sequence_id

    enum_field UInt8, status : Status = Status::Success
    int32 :length, value: ->{ key.bytesize }
    string :key, length: ->{ length }

    # Keep a reference to the remainder of the message
    protected setter binary : IO
    getter! binary : IO

    property! path : String

    def success
      status.success?
    end

    private def write_binary_io(io : IO)
      if binary?.nil?
        # Write from the file IO directly
        File.open(path) do |file_io|
          IO.copy(file_io, io)
        end
      else
        IO.copy(binary, io)
      end
    end

    def write(io : IO)
      result = super(io)
      write_binary_io(io)
      result
    end

    def to_slice
      io = IO::Memory.new
      io.write_bytes self
      write_binary_io(io)
      io.to_slice
    end

    def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::SystemEndian)
      data = super(io, format)
      data.binary = io
      data
    end

    def self.from_slice(bytes : Slice, format : IO::ByteFormat = IO::ByteFormat::SystemEndian)
      io = IO::Memory.new(bytes, writeable: false)
      from_io(io, format)
    end
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
        Debug        # Success
        DriverLoaded # Success
        DriverStatus
        Execute
        Ignore # Success
        Kill   # Success
        Load   # Success
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
        DebugMessage
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
          {{ response[0].stringify }} => {{ response[1].id }},
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

    struct Debug < Server::Request
      getter module_id : String

      def initialize(@module_id)
      end
    end

    struct Execute < Server::Request
      getter module_id : String
      getter payload : String

      def initialize(@module_id, @payload)
      end
    end

    struct Ignore < Server::Request
      getter module_id : String

      def initialize(@module_id)
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
      def initialize
      end
    end

    struct LoadedModules < Server::Request
      def initialize
      end
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

    struct DebugMessage < Client::Request
      getter module_id : String
      getter message : String

      def initialize(@module_id, @message)
      end
    end

    struct FetchBinary < Client::Request
      getter key : String

      def initialize(@key)
      end
    end

    struct ProxyRedis < Client::Request
      getter action : RedisAction
      getter hash_id : String
      getter key_name : String
      getter status_value : String?

      def initialize(@action, @hash_id, @key_name, @status_value)
      end
    end

    struct Register < Client::Request
      getter modules : Set(String)
      getter drivers : Set(String)

      def initialize(@modules, @drivers)
      end
    end

    struct SettingsAction < Client::Request
      getter module_id : String
      getter setting_name : String
      getter setting_value : String

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
      def initialize(@success)
      end
    end

    # Client Responses
    ############################################################################

    struct ExecuteResponse < Client::Response
      getter output : String?

      def initialize(@success, @output)
      end
    end

    struct DriverStatusResponse < Client::Response
      getter status : Core::ProcessManager::DriverStatus?

      def initialize(@status)
      end
    end

    struct LoadedModulesResponse < Client::Response
      getter modules : Hash(String, Array(String))

      def initialize(@modules)
      end
    end

    struct RunCountResponse < Client::Response
      getter count : Core::ProcessManager::Count

      def initialize(@count)
      end
    end

    struct SystemStatusResponse < Client::Response
      getter status : Core::ProcessManager::SystemStatus

      def initialize(@status)
      end
    end

    # Server Responses
    ############################################################################

    # Binary response constructor
    class BinaryBody
      getter key : String
      getter success : Bool

      getter! path : String
      getter! io : IO

      def initialize(@success, @key, @path = nil, @io = nil)
      end
    end

    struct RegisterResponse < Server::Response
      getter add_drivers : Array(String)
      getter remove_drivers : Array(String)
      getter add_modules : Array(Module)
      getter remove_modules : Array(String)

      alias Module = NamedTuple(key: String, module_id: String)

      def initialize(
        @success,
        @add_drivers = [] of String,
        @remove_drivers = [] of String,
        @add_modules = [] of Module,
        @remove_modules = [] of String
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

  macro request(message, expect, preserve_response = false)
    begin
      %response = send_request({{ message }})
      %success = %response.responds_to?(:success) ?  %response.success : true

      if %response.is_a?({{expect}}) && %success
        %response
      else
        Log.error { {
          {% for arg in @def.args %}
            {{arg.name}}: {{arg.name}}.is_a?(::Log::Metadata::Value::Type) ? {{arg.name.id}} : {{arg.name.id}}.to_s,
          {% end %}
          message: "{{@def.name}} failed",
        } }
        {% if preserve_response %}
          %response if %response.is_a?({{expect}})
        {% else %}
          nil
        {% end %}
      end
    rescue e
      Log.error { {
        {% for arg in @def.args %}
          {{arg.name}}: {{arg.name}}.is_a?(::Log::Metadata::Value::Type) ? {{arg.name.id}} : {{arg.name.id}}.to_s,
        {% end %}
        message: "{{@def.name}} errored",
      } }
      nil
    end
  end

  {% begin %}
    unwrap_subclasses(Request, Union(Server::Request, Client::Request))
    unwrap_subclasses(Response, Union(Server::Response, Client::Response, Message::Success, Message::BinaryBody))
  {% end %}
end
