
require "json"
# require "rest-api"

class Pulse::Heartbeat
  include JSON::Serializable

  getter drivers_qty : Int32
  getter zones_qty : Int32
  getter users_qty : Int32
  getter staff_api : Bool
  getter instance_type : String
  getter desks : Array(PlaceOS::Model::Zone)
  # add any other telemetry to collect here in future

  def initialize(
    @drivers_qty = PlaceOS::Model::Driver.count,
    @zones_qty = PlaceOS::Model::Zone.count,
    @users_qty = PlaceOS::Model::User.count,
    # @desks_qty = 
    @staff_api = true, # figure out how to find this
    @instance_type = "PROD"
  ) # and this # maybe an envar...

    # get desks
    @desks = [] of PlaceOS::Model::Zone
    # desks << PlaceOS::Model::Zone
    # @desk_qty =
    #  (PlaceOS::Model::Zone.count (where type == "desk"))
    
    # pp! @drivers_qty
    
    # health = PlaceOS::Api::Root.healthcheack?
    # pp! health
    # driversreq
  # add any other telemetry to collect here in future
  end
end