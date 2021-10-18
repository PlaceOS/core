require "../helper"

module PlaceOS::Core::Api
  describe Root, tags: "api" do
    describe "GET /api/core/v1" do
      it "health checks" do
        ctx = context("GET", "/api/core/v1/")
        Root.new(ctx, :index).index
        ctx.response.status_code.should eq 200
      end
    end

    describe "GET /api/core/v1/version" do
      it "returns service version" do
        ctx = context("GET", "/api/core/v1/version")
        ctx.response.output = IO::Memory.new
        Root.new(ctx, :version).version
        ctx.response.status_code.should eq 200
        version = PlaceOS::Model::Version.from_json(ctx.response.output.to_s)
        version.service.should eq "core"
      end
    end
  end
end
