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
      @startup : Bool = true,
      @logger : Logger = Logger.new(STDOUT)
    )
      super(@logger)
      @startup = false
    end

    def process_resource(repository) : Bool
      repository_name = repository.name.as(String)
      repository_uri = repository.uri.as(String)
      repository_commit = repository.commit_hash.as(String)

      success = begin
        ACAEngine::Drivers::Compiler.clone_and_install(
          repository: repository_name,
          repository_uri: repository_uri,
          username: @username,
          password: @password,
          working_dir: @working_dir,
          pull_if_exists: @startup, # Only pulls if starting up
        )

        # Refresh the repository model commit hash
        current_commit = repository_commit_hash(repository_name)

        unless current_commit == repository_commit
          repository.update_fields(commit_hash: current_commit)
        end

        true
      rescue e
        # Add cloning errors
        errors << {name: repository_name, reason: e.try &.message || ""}
        false
      end

      success
    end
  end
end
