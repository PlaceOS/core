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

  abstract struct Body
    include JSON::Serializable

    enum Type
      BasicResponse
      Exec
      Load
      Loaded
      Register
    end

    use_json_discriminator "type", {
      Type::BasicResponse => BasicResponse,
      Type::Exec          => Exec,
      Type::Load          => Load,
      Type::Loaded        => Loaded,
      Type::Register      => Register,
    }

    macro inherited
      {% unless @type.abstract? %}
        getter type : Type = PlaceOS::Edge::Protocol::Body::Type::{{@type.stringify.split("::").last.id}}
      {% end %}
    end
  end

  # Requests

  struct Exec < Body
    getter payload : String

    def initialize(@payload)
    end
  end

  struct Loaded < Body
    def initialize
    end
  end

  struct Register < Body
    def initialize
    end
  end

  # Responses

  abstract struct ResponseBody < Body
    getter success : Bool = true
  end

  struct BasicResponse < ResponseBody
    def initialize(@success : Bool)
    end
  end

  struct Load < ResponseBody
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
    alias Request = Loaded | Exec
    alias Response = Load | ResponseBody | BinaryBody
  end

  alias Request = Server::Request | Client::Request
  alias Response = Server::Response | Client::Response
  alias Message = Request | Response
end
