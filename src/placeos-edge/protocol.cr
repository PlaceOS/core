require "bindata"
require "json"

module PlaceOS::Edge::Protocol
  # Arbitray message on the wire
  alias Message = Text | Binary

  # Response messages
  alias Response = Text::Response | Binary

  # Request messages
  alias Request = Text::Loaded | Text::Register

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
      getter type : Type = Type::{{@type.stringify.split("::").last.id}}
    end

    enum Type
      Response
      Register
      Loaded
    end

    use_json_discriminator "type", {
      Type::Response => Response,
      Type::Loaded   => Loaded,
      Type::Register => Register,
    }

    struct Response < Text
      getter? success : Bool
      getter payload : String
    end

    struct Loaded < Request
    end

    struct Register < Request
    end
  end

  # Response message body formats
  #
  abstract struct ResponseBody
    include JSON::Serializable

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
end
