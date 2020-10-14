require "bindata"
require "json"

module PlaceOS::Edge::Protocol
  enum Type
    Response
  end

  private abstract struct Base
    include JSON::Serializable
    include JSON::Serializable::Strict

    getter message_id : UInt64

    macro inherited
      getter type : Type = Type::{{@type.stringify.split("::").last.id}}
    end

    use_json_discriminator "type", {
      Type::Response => Response,
    }
  end

  struct Response < Base
    getter? success : Bool
    getter payload : String
  end

  alias Message = Base | Binary

  class Binary < BinData
    endian big
    uint64 :message_id
    remaining_bytes :payload
  end
end
