require "action-controller/logger"
require "engine-drivers/compiler"
require "engine-drivers/git_commands"
require "engine-models"

require "./resource"

module ACAEngine
  class Core::Cloning < Core::Resource(Model::Repository)
    @startup : Bool = true
    @testing : Bool = false # Prevent redundant pulls/installs

    def initialize(
      @username : String? = nil,
      @password : String? = nil,
      @working_dir : String = ACAEngine::Drivers::Compiler.repository_dir,
      @logger : ActionController::Logger::TaggedLogger = ActionController::Logger::TaggedLogger.new(Logger.new(STDOUT)),
      @startup : Bool = false,
      @testing : Bool = false
    )
      super(@logger)
    end

    def self.clone_and_install(
      repository : Model::Repository,
      working_dir : String = ACAEngine::Drivers::Compiler.repository_dir,
      username : String? = nil,
      password : String? = nil,
      startup : Bool = false,
      testing : Bool = false,
      logger : ActionController::Logger::TaggedLogger = ActionController::Logger::TaggedLogger.new(Logger.new(STDOUT))
    )
      repository_id = repository.id.as(String)
      repository_name = repository.name.as(String)
      repository_uri = repository.uri.as(String)
      repository_commit = repository.commit_hash.as(String)

      ACAEngine::Drivers::Compiler.clone_and_install(
        repository: repository_name,
        repository_uri: repository_uri,
        username: username || repository.username,
        password: password || repository.password,
        working_dir: working_dir,
        pull_if_exists: !testing,
      )

      # Update commit hash if repository id maps to current node, or during startup
      current_commit = ACAEngine::Drivers::Helper.repository_commit_hash(repository_name)
      own_node = startup || ModuleManager.instance.discovery.own_node?(repository_id)
      if current_commit != repository_commit && own_node
        if startup
          logger.tag_warn("updating commit on repository during startup", name: repository_name)
        end

        # Refresh the repository model commit hash
        repository.update_fields(commit_hash: current_commit)
      end

      logger.tag_info("cloned repository", repository: repository_name, uri: repository_uri)
    end

    def process_resource(repository) : Resource::Result
      Cloning.clone_and_install(
        repository: repository,
        username: @username,
        password: @password,
        working_dir: @working_dir,
        logger: @logger,
        startup: @startup,
        testing: @testing,
      )

      Resource::Result::Success
    rescue e
      # Add cloning errors
      errors << {name: repository.name.as(String), reason: e.try &.message || ""}

      Resource::Result::Error
    end

    def start
      super
      @startup = false
      self
    end
  end
end
