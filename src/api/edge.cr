require "./application"

require "../placeos-core/module_manager"

module PlaceOS::Core::Api
  class Edge < Application
    base "/api/core/v1/edge/"

    getter module_manager : ModuleManager { ModuleManager.instance }

    # websocket handling edge connections
    @[AC::Route::WebSocket("/control")]
    def edge_control(
      socket,
      @[AC::Param::Info(description: "the edge this device is handling", example: "edge-1234")]
      edge_id : String,
    ) : Nil
      module_manager.manage_edge(edge_id, socket)
    end
  end
end
