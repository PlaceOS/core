require "../helper"

module PlaceOS::Core::Api
  describe Status, tags: "api" do
    namespace = Status::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "status/" do
      it "renders data about node" do
        _, driver, _, resource_manager = create_resources

        driver.reload!

        # TODO: Update to new binary names
        # binary = Compiler.executable_name(driver.file_name, driver.commit, driver.id.as(String))
        io = IO::Memory.new
        ctx = context("GET", namespace, json_headers)
        ctx.response.output = io
        Status.new(ctx).index

        ctx.response.status_code.should eq 200

        status = Core::Client::CoreStatus.from_json(ctx.response.output.to_s)

        status.run_count.local.modules.should eq 0
        status.run_count.local.drivers.should eq 0
        status.run_count.edge.should be_empty
        status.driver_binaries.should_not be_empty
      ensure
        resource_manager.try &.stop
      end
    end

    pending "status/driver"
    pending "status/load"
  end
end
