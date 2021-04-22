require "uuid"

require "./helper"

module PlaceOS::Core
  describe Cloning, tags: "resource" do
    it "switches branches" do
      initial_branch = "master"
      secondary_branch = "fixture"

      set_temporary_working_directory(fresh: true)
      folder_name = "private-drivers"

      Model::Repository.clear
      repo = Model::Generator.repository(type: Model::Repository::Type::Driver)
      repo.uri = "https://github.com/placeos/private-drivers"
      repo.name = "drivers"
      repo.branch = initial_branch
      repo.folder_name = folder_name
      repo.commit_hash = "HEAD~2"
      repo.save!

      cloner = Cloning.new(testing: true)

      cloner.process_resource(:created, repo)

      full_repository_path = File.join(Compiler.repository_dir, folder_name)

      # Check the cloning took place
      Dir.exists?(full_repository_path).should be_true
      Compiler::GitCommands.current_branch(full_repository_path).should eq initial_branch

      commit_hash = Compiler::Helper.repository_commit_hash(folder_name)
      Model::Repository.find!(repo.id.as(String)).commit_hash.should eq commit_hash

      repo.clear_changes_information

      repo.branch = secondary_branch
      repo.save!

      cloner.process_resource(:updated, repo)

      commit_hash = Compiler::Helper.repository_commit_hash(folder_name)
      Model::Repository.find!(repo.id.as(String)).commit_hash.should eq commit_hash

      Compiler::GitCommands.current_branch(full_repository_path).should eq secondary_branch
    end

    it "clones/deletes repositories" do
      set_temporary_working_directory(fresh: true)
      folder_name = "private-drivers"

      Model::Repository.clear
      repo = Model::Generator.repository(type: Model::Repository::Type::Driver)
      repo.uri = "https://github.com/placeos/private-drivers"
      repo.name = "drivers"
      repo.folder_name = folder_name
      repo.commit_hash = "HEAD"
      repo.save!

      cloner = Cloning.new(testing: true).start

      full_repository_path = File.join(Compiler.repository_dir, folder_name)

      # Check repository has been processed
      cloner.processed.size.should eq 1
      cloner.processed.first[:resource].id.should eq repo.id

      # Check the cloning took place
      Dir.exists?(full_repository_path).should be_true

      commit_hash = Compiler::Helper.repository_commit_hash(folder_name)
      Model::Repository.find!(repo.id.as(String)).commit_hash.should eq commit_hash

      repo.destroy

      sleep 0.1

      # Check the repository has been deleted
      Dir.exists?(full_repository_path).should be_false
    ensure
      cloner.try &.stop
    end
  end
end
