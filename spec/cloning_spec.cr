require "./helper"
require "uuid"

module ACAEngine::Core
  describe Cloning do
    it "clones repositories" do
      # Clear repository table
      ACAEngine::Model::Repository.clear

      repo = ACAEngine::Model::Generator.repository(type: ACAEngine::Model::Repository::Type::Driver)

      repo.uri = "https://github.com/example/test/"
      repo.name = "test"
      repo.save!

      temp_dir = "#{Dir.tempdir}/#{UUID.random}"
      path = "#{temp_dir}/#{repo.name}"

      cloner = Cloning.new(working_dir: temp_dir)

      # Check repository has been processed
      cloner.processed.size.should eq 1
      cloner.processed.first.id.should eq repo.id

      # Check the cloning took place
      Dir.exists?(path).should be_true

      # Remove repo
      `rm -r #{path}`
    end
  end
end
