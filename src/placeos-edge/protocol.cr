require "bindata"
require "json"

module PlaceOS::Edge::Protocol
  # Binary messages
  #
  class Binary < BinData
    endian big
    uint64 :sequence_id

    int32 :size, value: ->{ description.bytesize }
    string :description, length: ->{ size }

    remaining_bytes :payload
  end

  # Text messages
  #
  abstract struct Text
    include JSON::Serializable
    include JSON::Serializable::Strict

    getter sequence_id : UInt64

    macro inherited
      getter type : Type = PlaceOS::Edge::Protocol::Text::Type::{{@type.stringify.split("::").last.id}}
    end

    enum Type
      Response
      Register
      Loaded
    end

    struct Response < Text
      getter? success : Bool
      getter payload : String
    end

    use_json_discriminator "type", {
      Type::Response => Response,
      Type::Loaded   => Loaded,
      Type::Register => Register,
    }
  end

  # Messages

  struct Loaded < Text
  end

  struct Register < Text
  end

  # Messages by consumer

  module Client
    alias Request = Register
    alias Response = Text::Response
  end

  module Server
    alias Request = Loaded | Load
    alias Response = Text::Response | Binary
  end

  # Request messages
  alias Request = Server::Request | Client::Request

  # Response messages
  alias Response = Server::Response | Client::Response

  # Arbitray message on the wire
  alias Message = Text | Binary

  # Response message body formats
  #
  abstract struct ResponseBody
    include JSON::Serializable
  end

  struct Load < ResponseBody
    getter add_drivers : Array(String)
    getter remove_drivers : Array(String)

    getter add_modules : Array(String)
    getter remove_modules : Array(String)

    def initialize(
      @add_drivers = [] of String,
      @remove_drivers = [] of String,
      @add_modules = [] of String,
      @remove_modules = [] of String
    )
    end
  end
end
