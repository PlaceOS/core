require "../helper"

module ACAEngine::Core
  describe Api::Drivers, tags: "api" do
    namespace = Api::Drivers::NAMESPACE[0]
    with_server do
      describe "drivers/" do
        it "lists drivers" do
          create_resources

          result = Array(String).from_json(curl("GET", namespace).body)
          result.should eq [SPEC_DRIVER]
        end
      end

      describe "drivers/:id" do
        it "lists commits for a particular driver" do
          create_resources

          path = File.join(namespace, URI.encode_www_form(SPEC_DRIVER))
          commits = Array(ACAEngine::Drivers::GitCommands::Commit).from_json(curl("GET", path).body)
          commits.size.should eq(2)
        end
      end
    end
  end
end
