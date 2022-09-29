require "action-controller/logger"
# fixes issues with static builds on crystal 1.5.x
require "placeos-driver/core_ext"
require "log_helper"
require "uri/json"

# :nodoc:
abstract class PlaceOS::Driver; end

# :nodoc:
class PlaceOS::Driver::Protocol; end

require "./placeos-edge/*"

module PlaceOS::Edge
end
