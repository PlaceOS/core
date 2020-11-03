require "../helper"

require "../../src/placeos-edge"
require "../../src/placeos-edge/*"

# Set up websockets on a blocking bidirectional IO
#
def mock_sockets
  io_l, io_r = IO::Stapled.pipe
  ({HTTP::WebSocket.new(io_l), HTTP::WebSocket.new(io_r)})
end
