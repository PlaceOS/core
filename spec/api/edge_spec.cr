require "../helper"

module PlaceOS::Core::Api
  describe Edge, tags: "api" do
    client = AC::SpecHelper.client

    namespace = Edge::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    it "returns desired state snapshots for an edge" do
      _, _, mod = setup(role: PlaceOS::Model::Driver::Role::Service)
      resource_manager = PlaceOS::Core::ResourceManager.new(testing: true)
      resource_manager.start { }
      edge = PlaceOS::Model::Generator.edge.save!
      mod.edge_id = edge.id.as(String)
      mod.running = true
      mod.save!

      route = File.join(namespace, edge.id.as(String), "desired_state")
      response = client.get(route, headers: json_headers)
      response.status_code.should eq 200

      snapshot = PlaceOS::Edge::State::Snapshot.from_json(response.body)
      snapshot.edge_id.should eq edge.id
      snapshot.modules.map(&.module_id).should contain(mod.id.as(String))
      snapshot.drivers.should_not be_empty
    ensure
      resource_manager.try &.stop
    end

    it "returns not modified when the desired state is stale" do
      _, _, mod = setup(role: PlaceOS::Model::Driver::Role::Service)
      resource_manager = PlaceOS::Core::ResourceManager.new(testing: true)
      resource_manager.start { }
      edge = PlaceOS::Model::Generator.edge.save!
      mod.edge_id = edge.id.as(String)
      mod.running = true
      mod.save!

      route = File.join(namespace, edge.id.as(String), "desired_state")
      first = client.get(route, headers: json_headers)
      first.status_code.should eq 200
      snapshot = PlaceOS::Edge::State::Snapshot.from_json(first.body)

      headers = json_headers.dup
      headers["If-Modified-Since"] = HTTP.format_time(snapshot.last_modified)
      second = client.get(route, headers: headers)
      second.status_code.should eq 304
    ensure
      resource_manager.try &.stop
    end

    it "returns not found for an unknown edge snapshot request" do
      response = client.get(File.join(namespace, "edge-missing", "desired_state"), headers: json_headers)
      response.status_code.should eq 404
    end

    it "streams compiled driver binaries for an edge" do
      _, driver, mod = setup(role: PlaceOS::Model::Driver::Role::Service)
      resource_manager = PlaceOS::Core::ResourceManager.new(testing: true)
      resource_manager.start { }
      edge = PlaceOS::Model::Generator.edge.save!
      mod.edge_id = edge.id.as(String)
      mod.running = true
      mod.save!

      result = PlaceOS::Core::DriverResource.load(driver, PlaceOS::Core::DriverStore.new, true)
      route = File.join(namespace, edge.id.as(String), "drivers", File.basename(result.path))
      response = client.get(route, headers: json_headers)
      response.status_code.should eq 200
      response.headers["Content-Type"].should eq "application/octet-stream"
      response.body.bytesize.should be > 0
    ensure
      resource_manager.try &.stop
    end

    it "returns not found when the binary key does not exist" do
      edge = PlaceOS::Model::Generator.edge.save!
      route = File.join(namespace, edge.id.as(String), "drivers", "drivers_missing_deadbeef_arm64")
      response = client.get(route, headers: json_headers)
      response.status_code.should eq 404
    end
  end
end
