require "engine-rest-api/models"
require "engine-drivers/git_commands"
require "engine-drivers/compiler"

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
      repository_name = repository.name.as(String)
      repository_uri = repository.uri.as(String)

      result = ACAEngine::Drivers::GitCommands.clone(
        repository: repository_name,
        repository_uri: repository_uri,
        username: @username,
        password: @password,
        working_dir: @working_dir,
      )

      success = result[:exit_status] == 0

      # Add cloning errors
      errors << {name: repository_name, reason: result[:output]} unless success

      success
    end
  end
end
