require "engine-drivers/compiler"
require "engine-drivers/git_commands"
require "engine-drivers/helper"
require "semantic_version"
require "rethinkdb-orm"

require "./helper"

module ACAEngine::Core
  describe Compilation do
    context "startup" do
      # Set up a temporary directory
      temp_dir = set_temporary_working_directory

      # Repository metadata
      repository_uri = "https://github.com/aca-labs/private-crystal-engine-drivers"
      repository_name = repository_folder_name = "drivers"

      # Clone driver repository
      ACAEngine::Drivers::Compiler.clone_and_install(
        repository: repository_name,
        repository_uri: repository_uri,
        pull_if_exists: false
      )

      # Grab commit hash from cloned driver
      repository_commit_hash = ACAEngine::Drivers::Helper.repository_commit_hash(repository_name)

      # Create models
      Model::Repository.clear
      Model::Driver.clear

      repository = Model::Generator.repository(type: Model::Repository::Type::Driver)
      repository.uri = repository_uri
      repository.name = repository_name
      repository.folder_name = repository_folder_name
      repository.commit_hash = repository_commit_hash
      repository.save!

      driver = Model::Driver.new(
        name: "spec_helper",
        role: Model::Driver::Role::Logic,
        commit: repository_commit_hash,
        version: SemanticVersion.new(major: 1, minor: 0, patch: 0),
        module_name: "PrivateHelper",
        file_name: "drivers/aca/private_helper.cr",
      )
      driver.repository = repository
      driver.save!

      # Commence cloning
      compiler = Compilation.new

      it "compiles drivers" do
        compiler.processed.size.should eq 1
        compiler.processed.first.id.should eq driver.id

        # Ensure working directory is set to the original temporary directory
        set_temporary_working_directory(temp_dir)
        ACAEngine::Drivers::Helper.compiled?(driver.file_name.as(String), repository_commit_hash).should be_true
      end

      Spec.after_suite do
        # Remove temporary directory
        puts `rm -rf #{temp_dir}`
      end
    end
  end
end
