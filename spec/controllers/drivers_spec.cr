require "../helper"

module ACAEngine::Core
  describe Api::Drivers do
    with_server do
      describe "drivers/" do
        it "lists drivers" do
          create_resources

          result = Array(String).from_json(curl("GET", "/api/core/v1/drivers").body)
          result.should eq [SPEC_DRIVER]
        end
      end

      describe "drivers/:id" do
        it "lists commits for a particular driver" do
          create_resources

          uri_safe = URI.encode_www_form(SPEC_DRIVER)
          commits = Array(ACAEngine::Drivers::GitCommands::Commit).from_json(curl("GET", "/api/core/v1/drivers/" + uri_safe).body)
          commits.size.should eq(2)
        end
      end
    end
  end
end
