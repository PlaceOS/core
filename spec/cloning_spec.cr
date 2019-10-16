require "uuid"

require "./helper"

module ACAEngine::Core
  describe Cloning do
    context "startup" do
      # Set up a temporary directory
      temp_dir = set_temporary_working_directory

      ACAEngine::Model::Repository.clear
      repo = ACAEngine::Model::Generator.repository(type: ACAEngine::Model::Repository::Type::Driver)
      repo.uri = "https://github.com/aca-labs/private-crystal-engine-drivers"
      repo.name = "drivers"
      repo.folder_name = "drivers"
      repo.commit_hash = "head"
      repo.save!
      cloner = Cloning.new

      it "updates commit hash of repository" do
        commit_hash = ACAEngine::Drivers::Helper.repository_commit_hash(repo.name.as(String))
        ACAEngine::Model::Repository.find!(repo.id).commit_hash.should eq commit_hash
      end

      it "clones repositories" do
        # Check repository has been processed
        cloner.processed.size.should eq 1
        cloner.processed.first.id.should eq repo.id

        # Check the cloning took place
        Dir.exists?(ACAEngine::Drivers::Compiler.drivers_dir).should be_true
      end

      Spec.after_suite do
        # Remove temporary directory
        puts `rm -rf #{temp_dir}`
      end
    end
  end
end
