require "engine-drivers/compiler"
require "engine-drivers/git_commands"
require "engine-rest-api/models"

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

      success = begin
        ACAEngine::Drivers::Compiler.clone_and_install(
          repository: repository_name,
          repository_uri: repository_uri,
          username: @username,
          password: @password,
          working_dir: @working_dir,
        )

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
