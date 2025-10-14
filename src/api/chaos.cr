require "./application"

require "../placeos-core/module_manager"

module PlaceOS::Core::Api
  class Chaos < Application
    base "/api/core/v1/chaos/"

    getter module_manager : ModuleManager { ModuleManager.instance }

    # Terminate a process by executable path
    @[AC::Route::POST("/terminate")]
    def terminate(
      @[AC::Param::Info(name: path, description: "the driver executable name", example: "drivers_place_meet_c54390a")]
      driver_key : String,
      @[AC::Param::Info(description: "optionally provide the edge id the driver is running on", example: "edge-12345")]
      edge_id : String? = nil,
    ) : Nil
      raise Error::NotFound.new("no process manager found for #{driver_key}") unless manager = module_manager.process_manager(driver_key, edge_id)
      manager.kill(driver_key)
    end
  end
end
