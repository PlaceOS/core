require "uuid"

require "./helper"

module ACAEngine::Core
  describe Cloning do
    describe "startup" do
      it "clones repositories" do
        set_temporary_working_directory(fresh: true)

        ACAEngine::Model::Repository.clear
        repo = ACAEngine::Model::Generator.repository(type: ACAEngine::Model::Repository::Type::Driver)
        repo.uri = "https://github.com/acaengine/private-drivers"
        repo.name = "drivers"
        repo.folder_name = "drivers"
        repo.commit_hash = "head"
        repo.save!

        cloner = Cloning.new(testing: true, logger: LOGGER).start

        # Check repository has been processed
        cloner.processed.size.should eq 1
        cloner.processed.first.id.should eq repo.id

        # Check the cloning took place
        Dir.exists?(ACAEngine::Drivers::Compiler.drivers_dir).should be_true

        commit_hash = ACAEngine::Drivers::Helper.repository_commit_hash(repo.name.as(String))
        ACAEngine::Model::Repository.find!(repo.id).commit_hash.should eq commit_hash

        cloner.stop
      end
    end
  end
end
