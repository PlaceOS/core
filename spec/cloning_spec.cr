require "./helper"
require "uuid"

module Engine::Core
  describe Cloning do
    it "clones repositories" do
      # Clear repository table
      Engine::Model::Repository.clear

      repo = Engine::Model::Generator.repository(type: Engine::Model::Repository::Type::Driver)

      repo.uri = "https://github.com/example/test/"
      repo.name = "test"
      repo.save!

      temp_dir = "#{Dir.tempdir}/#{UUID.random}"
      path = "#{temp_dir}/#{repo.name}"

      Cloning.new(working_dir: temp_dir)

      Dir.exists?(path).should be_true

      # Remove repo
      `rm -r #{path}`
    end
  end
end
