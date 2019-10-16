require "engine-drivers/compiler"
require "engine-drivers/git_commands"
require "engine-drivers/helper"
require "semantic_version"
require "rethinkdb-orm"

require "./helper"

module ACAEngine::Core
  describe Compilation do
    it "compiles drivers" do
      # Clear repository, driver table
      Model::Repository.clear
      Model::Driver.clear

      begin
        repository = Model::Repository.new(
          name: "drivers",
          type: Model::Repository::Type::Driver,
          folder_name: "drivers",
          description: Faker::Hacker.noun,
          uri: "https://github.com/aca-labs/crystal-engine-drivers",
          commit_hash: "head",
        ).save!

        driver = Model::Driver.new(
          name: "spec_helper",
          role: Model::Driver::Role::Logic,
          commit: "head",
          version: SemanticVersion.new(major: 1, minor: 0, patch: 0),
          module_name: "Helper",
          file_name: "drivers/aca/spec_helper.cr"
        )

        driver.repository = repository

        driver.save!
      rescue e : RethinkORM::Error::DocumentInvalid
        puts(e.try &.model.try &.errors)
        raise e
      end

      compiler = Compilation.new
      compiler.processed.size.should eq 1
      compiler.processed.first.id.should eq driver.id
      ACAEngine::Drivers::Helper.compiled?(driver.file_name.as(String), driver.commit.as(String)).should be_true
    end
  end
end
