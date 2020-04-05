require "../helper"

module PlaceOS::Core
  describe Api::Status do
    namespace = Api::Drivers::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "status/" do
      it "renders data about node" do
        repo, driver, _ = create_resources

        driver.reload!

        driver_file = driver.file_name.as(String)
        driver_id = driver.id.as(String)
        commit = driver.commit.as(String)
        binary = Drivers::Compiler.executable_name(driver_file, commit, driver_id)
        io = IO::Memory.new
        ctx = context("GET", namespace, json_headers)
        ctx.response.output = io
        Api::Status.new(ctx).index

        ctx.response.status_code.should eq 200

        status = Core::Client::CoreStatus.from_json(ctx.response.output.to_s)

        status.compiled_drivers.should contain binary
        status.available_repositories.should contain repo.folder_name
        status.running_drivers.should eq 0
        status.module_instances.should eq 0
      end

      pending "deletes standalone driver binary used for metadata"
    end

    pending "status/driver"
    pending "status/load"
  end
end
