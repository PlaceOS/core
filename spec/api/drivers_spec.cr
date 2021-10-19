require "../helper"

module PlaceOS::Core::Api
  describe Drivers, tags: "api" do
    namespace = Drivers::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "drivers/" do
      it "lists drivers" do
        repo, _, _, resource_manager = create_resources

        path = "#{namespace}?repository=#{repo.folder_name}"
        ctx = context("GET", path, json_headers)
        ctx.response.output = IO::Memory.new
        Drivers.new(ctx, :index).index

        result = begin
          Array(String).from_json(ctx.response.output.to_s)
        rescue
          nil
        end

        ctx.response.status_code.should eq 200
        result.should_not be_nil
        result.not_nil!.sort.should eq ["drivers/place/dispatch_example.cr", "drivers/place/edge_demo.cr", "drivers/place/feature_test.cr", "drivers/place/private_helper.cr"]
      ensure
        resource_manager.try &.stop
      end
    end

    describe "drivers/:file_name/compiled" do
      it "checks if a driver has been compiled" do
        repo, driver, _, resource_manager = create_resources
        uri = URI.encode_www_form(SPEC_DRIVER)

        params = HTTP::Params{
          "repository" => repo.folder_name,
          "commit"     => driver.commit,
          "tag"        => driver.id.as(String),
        }

        path = File.join(namespace, uri, "/compiled?#{params}")
        ctx = context("GET", path, json_headers)
        ctx.route_params = {"file_name" => uri}
        ctx.response.output = IO::Memory.new
        Drivers.new(ctx, :compiled).compiled

        ctx.response.status_code.should eq 200
        Bool.from_json(ctx.response.output.to_s).should be_true
      ensure
        resource_manager.try &.stop
      end
    end

    describe "drivers/:repository/branches" do
      it "404s if the repository has not been cloned" do
        directory = "doesnotexist"
        path = File.join(namespace, directory, "branches")
        ctx = context("GET", path, json_headers)
        ctx.route_params = {"repository" => directory}
        ctx.response.output = IO::Memory.new

        Drivers.new(ctx, :branches).branches

        ctx.response.status_code.should eq 404
      end

      it "lists the branches on a cloned repository" do
        repo, _, _, resource_manager = create_resources
        directory = repo.folder_name
        path = File.join(namespace, directory, "branches")
        ctx = context("GET", path, json_headers)
        ctx.route_params = {"repository" => directory}
        ctx.response.output = IO::Memory.new
        Drivers.new(ctx, :branches).branches

        ctx.response.status_code.should eq 200
        branches = Array(String).from_json(ctx.response.output.to_s)
        branches.should_not be_empty
        branches.should contain("master")
      ensure
        resource_manager.try &.stop
      end
    end

    describe "drivers/:file_name" do
      it "lists commits for a particular driver" do
        repo, _, _, resource_manager = create_resources
        uri = URI.encode_www_form(SPEC_DRIVER)

        path = File.join(namespace, uri, "?repository=#{repo.folder_name}")
        ctx = context("GET", path, json_headers)
        ctx.route_params = {"file_name" => uri}
        ctx.response.output = IO::Memory.new
        Drivers.new(ctx, :index).show

        ctx.response.status_code.should eq 200

        expected = Compiler::Git.commits(URI.decode(uri), repo.folder_name, Compiler.repository_dir, 50)
        result = Array(Compiler::Git::Commit).from_json(ctx.response.output.to_s)
        result.should eq expected
      ensure
        resource_manager.try &.stop
      end
    end
  end
end
