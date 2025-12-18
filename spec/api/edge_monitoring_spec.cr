require "../helper"

module PlaceOS::Core::Api
  describe EdgeMonitoring, tags: "api" do
    client = AC::SpecHelper.client

    namespace = EdgeMonitoring::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "POST /cleanup" do
      it "responds with success message" do
        response = client.post("#{namespace}cleanup", headers: json_headers, body: {hours: 24}.to_json)
        response.status_code.should eq 200

        result = JSON.parse(response.body)
        result["success"].as_bool.should be_true
        result["message"].as_s.should contain("24 hours")
        result["timestamp"].as_s.should_not be_empty
      end

      it "accepts custom hours parameter" do
        response = client.post("#{namespace}cleanup?hours=48", headers: json_headers)
        response.status_code.should eq 200

        result = JSON.parse(response.body)
        result["success"].as_bool.should be_true
        result["message"].as_s.should contain("48 hours")
      end
    end

    describe "GET /summary" do
      it "returns error summary statistics" do
        response = client.get("#{namespace}summary", headers: json_headers)
        response.status_code.should eq 200

        result = JSON.parse(response.body)
        result["total_edges"].as_i.should be >= 0
        result["connected_edges"].as_i.should be >= 0
        result["edges_with_errors"].as_i.should be >= 0
        result["total_errors_24h"].as_i.should be >= 0
        result["total_modules"].as_i.should be >= 0
        result["failed_modules"].as_i.should be >= 0
        result["timestamp"].as_s.should_not be_empty
      end
    end
  end
end
