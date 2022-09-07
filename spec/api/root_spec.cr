require "../helper"

module PlaceOS::Core::Api
  describe Root, tags: "api" do
    client = AC::SpecHelper.client

    describe "GET /api/core/v1" do
      it "health checks" do
        response = client.get("/api/core/v1/")
        response.status_code.should eq 200
      end
    end

    describe "GET /api/core/v1/version" do
      it "returns service version" do
        response = client.get("/api/core/v1/version")
        response.status_code.should eq 200
        version = PlaceOS::Model::Version.from_json(response.body)
        version.service.should eq "core"
      end
    end
  end
end
