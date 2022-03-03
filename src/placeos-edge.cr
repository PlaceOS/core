require "action-controller/logger"
require "log_helper"
require "uri/json"

# :nodoc:
abstract class PlaceOS::Driver; end

# :nodoc:
class PlaceOS::Driver::Protocol; end

require "./placeos-edge/*"

module PlaceOS::Edge
end
