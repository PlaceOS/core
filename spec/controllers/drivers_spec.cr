require "../helper"

module PlaceOS::Core
  describe Api::Drivers, tags: "api" do
    namespace = Api::Drivers::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "drivers/" do
      it "lists drivers" do
        repo, _, _ = create_resources

        path = "#{namespace}?repository=#{repo.folder_name}"
        io = IO::Memory.new
        ctx = context("GET", path, json_headers)
        ctx.response.output = io
        Api::Drivers.new(ctx, :index).index

        result = begin
          Array(String).from_json(ctx.response.output.to_s)
        rescue
          nil
        end

        ctx.response.status_code.should eq 200

        result.should eq [SPEC_DRIVER]
      end
    end

    describe "drivers/:id" do
      it "lists commits for a particular driver" do
        repo, _, _ = create_resources
        uri = URI.encode_www_form(SPEC_DRIVER)

        io = IO::Memory.new
        path = File.join(namespace, uri, "?repository=#{repo.folder_name}")
        ctx = context("GET", path, json_headers)
        ctx.route_params = {"id" => uri}
        ctx.response.output = io
        Api::Drivers.new(ctx, :index).show

        ctx.response.status_code.should eq 200

        expected = PlaceOS::Drivers::Helper.commits(URI.decode(uri), repo.folder_name, 50)
        result = Array(PlaceOS::Drivers::GitCommands::Commit).from_json(ctx.response.output.to_s)
        result.should eq expected
      end
    end
  end
end
