require "../helper"

module PlaceOS::Core::Api
  describe BuildMonitor, tags: "api" do
    client = AC::SpecHelper.client

    describe "GET /api/core/v1/build" do
      it "monitor job status" do
        response = client.get("/api/core/v1/build/monitor")
        response.status_code.should eq 200
      end
      it "monitor job status" do
        response = client.get("/api/core/v1/build/cancel/asdfasfasfasd")
        response.status_code.should eq 404
      end
    end
  end
end
