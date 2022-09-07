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
        repo, driver, _, resource_manager = create_resources

        driver.reload!

        binary = Compiler.executable_name(driver.file_name, driver.commit, driver.id.as(String))
        response = client.get(namespace, headers: json_headers)
        response.status_code.should eq 200

        status = Core::Client::CoreStatus.from_json(response.body)

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
