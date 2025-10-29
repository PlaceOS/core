require "../helper"

module PlaceOS::Core::Api
  describe Status, tags: "api" do
    client = AC::SpecHelper.client

    namespace = Status::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "status/" do
      it "renders data about node" do
        _, driver, _, resource_manager = create_resources

        driver.reload!

        response = client.get(namespace, headers: json_headers)
        response.status_code.should eq 200

        status = Status::Statistics.from_json(response.body)

        status.run_count.local.modules.should eq 0
        status.run_count.local.drivers.should eq 0
        status.run_count.edge.should be_empty
      ensure
        resource_manager.try &.stop
      end

      pending "deletes standalone driver binary used for metadata"
    end

    pending "status/driver"
    pending "status/load"

    describe "edge endpoints" do
      it "GET /edge/:edge_id/errors returns errors for specific edge" do
        edge_id = "test-edge-1"

        response = client.get("#{namespace}edge/#{edge_id}/errors", headers: json_headers)
        response.status_code.should eq 200

        # Just verify it's valid JSON array
        result = JSON.parse(response.body)
        result.should be_a(JSON::Any)
        result.as_a.should be_a(Array(JSON::Any))
      end

      it "GET /edge/:edge_id/modules/status returns module status for specific edge" do
        edge_id = "test-edge-1"

        response = client.get("#{namespace}edge/#{edge_id}/modules/status", headers: json_headers)
        response.status_code.should eq 200

        # Just verify it's valid JSON and has expected fields
        result = JSON.parse(response.body)
        result.should be_a(JSON::Any)
        result["edge_id"].as_s.should eq edge_id
      end

      it "GET /edges/health returns health status for all edges" do
        response = client.get("#{namespace}edges/health", headers: json_headers)
        response.status_code.should eq 200

        # Just verify it's valid JSON and has the expected structure
        result = JSON.parse(response.body)
        result.should be_a(JSON::Any)
      end

      it "GET /edges/connections returns connection metrics for all edges" do
        response = client.get("#{namespace}edges/connections", headers: json_headers)
        response.status_code.should eq 200

        # Just verify it's valid JSON
        result = JSON.parse(response.body)
        result.should be_a(JSON::Any)
      end

      it "GET /edges/errors returns errors from all edges" do
        response = client.get("#{namespace}edges/errors", headers: json_headers)
        response.status_code.should eq 200

        # Just verify it's valid JSON
        result = JSON.parse(response.body)
        result.should be_a(JSON::Any)
      end

      it "GET /edges/modules/failures returns module failures from all edges" do
        response = client.get("#{namespace}edges/modules/failures", headers: json_headers)
        response.status_code.should eq 200

        # Just verify it's valid JSON
        result = JSON.parse(response.body)
        result.should be_a(JSON::Any)
      end

      it "GET /edges/statistics returns overall edge statistics" do
        response = client.get("#{namespace}edges/statistics", headers: json_headers)
        response.status_code.should eq 200

        # Just verify it's valid JSON and has expected fields
        result = JSON.parse(response.body)
        result.should be_a(JSON::Any)
        result["total_edges"].as_i.should be >= 0
        result["connected_edges"].as_i.should be >= 0
        result["disconnected_edges"].as_i.should be >= 0
      end
    end
  end
end
