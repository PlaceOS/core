require "./application"

require "../placeos-core/resources/modules"

module PlaceOS::Core::Api
  class Edge < Application
    base "/api/core/v1/edge/"

    getter module_manager : Resources::Modules { Resources::Modules.instance }

    ws "/control" do |socket|
      edge_id = params["edge_id"]
      module_manager.manage_edge(edge_id, socket)
    end
  end
end
