require "../helper"

module PlaceOS::Core::Api
  describe Root, tags: "api" do
    client = AC::SpecHelper.client

    describe "GET /" do
      it "responds for liveness probes regardless of startup state" do
        Root.resource_manager.stop

        response = client.get("/")
        response.status_code.should eq 200
      end
    end

    describe "GET /api/core/v1/ready" do
      it "returns 503 until startup has completed" do
        Root.resource_manager.stop

        response = client.get("/api/core/v1/ready")
        response.status_code.should eq 503
      end
    end

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
