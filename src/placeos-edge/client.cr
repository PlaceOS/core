require "./protocol"

module PlaceOS::Edge
  # Secret used to register with PlaceOS
  private EDGE_SECRET = ENV["PLACE_EDGE_SECRET"]? || abort "missing PLACE_EDGE_SECRET in environment"

  class Client
    def initialize
    end
  end
end
