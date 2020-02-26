require "../helper"

module ACAEngine::Core
  describe Api::Status, tags: "api" do
    with_server do
      it "status/" do
        repo, driver, _ = create_resources
        client = Core::Client.new("localhost", 6000)
        status = client.core_status
        status.should be_a Core::Client::CoreStatus

        driver_file = driver.file_name.as(String)
        commit = Drivers::Helper.file_commit_hash(driver_file)
        binary = Drivers::Compiler.executable_name(driver_file, commit)

        status.compiled_drivers.should eq [binary]
        status.available_repositories.should eq [repo.name]
        status.running_drivers.should eq 0
        status.module_instances.should eq 0
        status.unavailable_repositories.size.should eq 0
        status.unavailable_drivers.size.should eq 0
      end
    end
    pending "status/driver" do
    end
    pending "status/load" do
    end
  end
end
