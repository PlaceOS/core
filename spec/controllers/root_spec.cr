require "../helper"

module PlaceOS::Core::Api
  with_server do
    it "should check version" do
      result = curl("GET", "/api/core/v1/version")
      result.status_code.should eq 200
      PlaceOS::Model::Version.from_json(result.body).service.should eq "core"
    end
  end
end
