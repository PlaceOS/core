require "./helper"
require "engine-drivers/git_commands"
require "engine-drivers/compiler"
require "semantic_version"
require "rethinkdb-orm"

module ACAEngine::Core
  describe Compilation do
    it "compiles drivers" do
      # Clear repository, driver table
      ACAEngine::Model::Repository.clear
      ACAEngine::Model::Driver.clear

      bin_dir = "#{Dir.tempdir}/#{UUID.random}/drivers"
      drivers_dir = File.expand_path("./lib/engine-drivers")
      repository_dir = "#{drivers_dir}/repositories"

      begin
        driver = Model::Driver.new(
          name: "spec_helper",
          role: Model::Driver::Role::Logic,
          commit: "head",
          version: SemanticVersion.new(major: 1, minor: 0, patch: 0),
          module_name: "Helper",
        )

        # pp! driver

        driver.save!
      rescue e : RethinkORM::Error::DocumentInvalid
        puts(e.try &.model.try &.errors)
        raise e
      end

      compiler = Compilation.new(
        repository_dir: repository_dir,
        drivers_dir: drivers_dir,
        bin_dir: bin_dir,
      )

      compiler.processed.size.should eq 1
      compiler.processed.first.id.should eq driver.id

      `rm -rf #{bin_dir}`
    end
  end
end
