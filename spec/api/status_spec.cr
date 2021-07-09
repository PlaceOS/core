require "../helper"

module PlaceOS::Core
  describe Api::Status do
    namespace = Api::Drivers::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "status/" do
      it "renders data about node" do
        repo, driver, _, resource_manager = create_resources

        driver.reload!

        binary = Compiler.executable_name(driver.file_name, driver.commit, driver.id.as(String))
        io = IO::Memory.new
        ctx = context("GET", namespace, json_headers)
        ctx.response.output = io
        Api::Status.new(ctx).index

        ctx.response.status_code.should eq 200

        status = Core::Client::CoreStatus.from_json(ctx.response.output.to_s)

        status.compiled_drivers.should contain binary
        status.available_repositories.should contain repo.folder_name

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
  end
end
