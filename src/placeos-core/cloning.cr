require "placeos-compiler/drivers/compiler"
require "placeos-compiler/drivers/git_commands"
require "file_utils"
require "placeos-models"

require "./module_manager"
require "./resource"

module PlaceOS
  class Core::Cloning < Core::Resource(Model::Repository)
    private getter? startup : Bool = true
    private getter? testing : Bool = false # Prevent redundant pulls/installs

    def initialize(
      @username : String? = nil,
      @password : String? = nil,
      @working_dir : String = Drivers::Compiler.repository_dir,
      @startup : Bool = true,
      @testing : Bool = false
    )
      super()
    end

    def process_resource(event) : Resource::Result
      repository = event[:resource]

      # Ignore interface repositories
      return Result::Skipped if repository.repo_type == Model::Repository::Type::Interface

      case event[:action]
      when Action::Created, Action::Updated
        # Clone and install the repository
        Cloning.clone_and_install(
          repository: repository,
          username: @username,
          password: @password,
          working_dir: @working_dir,
          startup: startup?,
          testing: testing?,
        )
      when Action::Deleted
        # Delete the repository folder
        Cloning.delete_repository(
          repository: repository,
          working_dir: @working_dir,
        )
      end.as(Result)
    rescue e
      # Add cloning errors
      raise Resource::ProcessingError.new(event[:resource].name, "#{e} #{e.message}")
    end

    def self.clone_and_install(
      repository : Model::Repository,
      working_dir : String = Drivers::Compiler.repository_dir,
      username : String? = nil,
      password : String? = nil,
      startup : Bool = false,
      testing : Bool = false
    )
      repository_id = repository.id.as(String)
      # NOTE:: we want to use folder name at this level
      repository_folder_name = repository.folder_name.as(String)
      repository_uri = repository.uri.as(String)
      repository_commit = repository.commit_hash.as(String)

      Drivers::Compiler.clone_and_install(
        repository: repository_folder_name,
        repository_uri: repository_uri,
        username: repository.username || username,
        password: repository.password || password,
        working_dir: working_dir,
        pull_if_exists: !testing,
      )

      # Update commit hash if repository id maps to current node, or during startup
      current_commit = Drivers::Helper.repository_commit_hash(repository_folder_name)
      own_node = startup || ModuleManager.instance.discovery.own_node?(repository_id)

      if current_commit != repository_commit && own_node
        if startup
          Log.warn { {
            message:           "updating commit on repository during startup",
            current_commit:    current_commit,
            repository_commit: repository_commit,
            folder_name:       repository_folder_name,
          } }
        else
          Log.info { {
            message:           "updating commit on repository",
            current_commit:    current_commit,
            repository_commit: repository_commit,
            folder_name:       repository_folder_name,
          } }
        end

        # Refresh the repository model commit hash
        repository.update_fields(commit_hash: current_commit)
      end

      Log.info { {
        message:    "cloned repository",
        commit:     current_commit,
        repository: repository_folder_name,
        uri:        repository_uri,
      } }

      Result::Success
    end

    def self.delete_repository(
      repository : Model::Repository,
      working_dir : String = Drivers::Compiler.repository_dir
    )
      repository_folder_name = repository.is_a?(String) ? repository : repository.folder_name.as(String)
      working_dir = File.expand_path(working_dir)
      repository_dir = File.expand_path(File.join(working_dir, repository_folder_name))

      # Ensure we `rmdir` a sane folder
      # - don't delete root
      # - don't delete working directory
      safe_directory = repository_dir.starts_with?(working_dir) &&
                       repository_dir != "/" &&
                       !repository_folder_name.empty? &&
                       !repository_folder_name.includes?("/") &&
                       !repository_folder_name.includes?(".")

      return Result::Error unless safe_directory

      if Dir.exists?(repository_dir)
        begin
          FileUtils.rm_rf(repository_dir)
          Result::Success
        rescue
          Result::Error
        end
      else
        Result::Skipped
      end
    end

    def start
      super
      @startup = false
      self
    end
  end
end
