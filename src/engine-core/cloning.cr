require "engine-drivers/compiler"
require "engine-drivers/git_commands"
require "engine-models"

require "./resource"

module ACAEngine
  class Core::Cloning < Core::Resource(Model::Repository)
    def initialize(
      @username : String? = nil,
      @password : String? = nil,
      @working_dir : String = ACAEngine::Drivers::Compiler.repository_dir,
      @logger : Logger = Logger.new(STDOUT)
    )
      super(@logger)
    end

    def process_resource(repository) : Bool
      Cloning.clone_and_install(
        repository: repository,
        username: @username,
        password: @password,
        working_dir: @working_dir
      )

      true
    rescue e
      # Add cloning errors
      errors << {name: repository.name.as(String), reason: e.try &.message || ""}

      false
    end

    def self.clone_and_install(
      repository : Model::Repository,
      working_dir : String = ACAEngine::Drivers::Compiler.repository_dir,
      username : String? = nil,
      password : String? = nil
    )
      repository_name = repository.name.as(String)
      repository_uri = repository.uri.as(String)
      repository_commit = repository.commit_hash.as(String)

      ACAEngine::Drivers::Compiler.clone_and_install(
        repository: repository_name,
        repository_uri: repository_uri,
        username: username || repository.username,
        password: password || repository.password,
        working_dir: working_dir,
      )

      # Refresh the repository model commit hash
      current_commit = ACAEngine::Drivers::Helper.repository_commit_hash(repository_name)
      unless current_commit == repository_commit
        repository.update_fields(commit_hash: current_commit)
      end
    end
  end
end
