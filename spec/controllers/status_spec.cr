require "../helper"

module PlaceOS::Core
  describe Api::Status do
    namespace = Api::Drivers::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    it "status/" do
      repo, driver, _ = create_resources

      driver_file = driver.file_name.as(String)
      commit = Drivers::Helper.file_commit_hash(driver_file)
      binary = Drivers::Compiler.executable_name(driver_file, commit)

      io = IO::Memory.new
      ctx = context("GET", namespace, json_headers)
      ctx.response.output = io
      Api::Status.new(ctx).index
      status = Core::Client::CoreStatus.from_json(ctx.response.output.to_s)

      status.compiled_drivers.should eq [binary]
      status.available_repositories.should eq [repo.name]
      status.running_drivers.should eq 0
      status.module_instances.should eq 0
    end

    pending "status/driver"
    pending "status/load"
  end
end
