require "./application"

require "../placeos-core/module_manager"

module PlaceOS::Core::Api
  class Edge < Application
    base "/api/core/v1/edge/"

    getter module_manager : ModuleManager { ModuleManager.instance }

    ws "/control" do |socket|
      edge_id = params["edge_id"]
      module_manager.manage_edge(edge_id, socket)
    end
  end
end
