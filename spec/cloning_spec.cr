require "uuid"

require "./helper"

module ACAEngine::Core
  describe Cloning, tags: "resource" do
    it "clones/deletes repositories" do
      set_temporary_working_directory(fresh: true)

      Model::Repository.clear
      repo = Model::Generator.repository(type: Model::Repository::Type::Driver)
      repo.uri = "https://github.com/acaengine/private-drivers"
      repo.name = "drivers"
      repo.folder_name = "drivers"
      repo.commit_hash = "head"
      repo.save!

      cloner = Cloning.new(testing: true, logger: LOGGER).start

      # Check repository has been processed
      cloner.processed.size.should eq 1
      cloner.processed.first[:resource].id.should eq repo.id

      # Check the cloning took place
      Dir.exists?(Drivers::Compiler.drivers_dir).should be_true

      commit_hash = Drivers::Helper.repository_commit_hash(repo.name.as(String))
      Model::Repository.find!(repo.id).commit_hash.should eq commit_hash

      repo.destroy
      sleep 0.5
      # Check the repository has been deleted
      Dir.exists?(Drivers::Compiler.drivers_dir).should be_false
      cloner.stop

      cloner.stop
    end
  end
end
