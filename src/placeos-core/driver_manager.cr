require "placeos-models"
require "placeos-resource"
require "./module_manager"
require "./driver_manager/**"

module PlaceOS::Core
  class DriverResource < Resource(Model::Driver)
    private getter? startup : Bool = true
    private getter module_manager : ModuleManager
    private getter store : DriverStore
    private getter lock : Mutex = Mutex.new

    def initialize(
      @startup : Bool = true,
      @binary_dir : String = "#{Dir.current}/bin/drivers",
      @module_manager : ModuleManager = ModuleManager.instance,
    )
      @store = DriverStore.new
      buffer_size = System.cpu_count.to_i
      super(buffer_size)
    end

    def process_resource(action : Resource::Action, resource driver : Model::Driver) : Resource::Result
      case action
      in .created?, .updated?
        result = DriverResource.load(driver, store, startup?, module_manager)
        unless result.success
          if driver.compilation_output.nil? || driver.recompile_commit? || driver.commit_changed?
            driver.update_fields(compilation_output: result.output)
          end
          raise Resource::ProcessingError.new(driver.name, result.output)
        end

        driver.update_fields(compilation_output: nil) unless driver.compilation_output.nil?
        Resource::Result::Success
      in .deleted?
        DriverResource.remove_driver(driver, store)
        Result::Skipped
      end
    rescue exception
      raise Resource::ProcessingError.new(driver.name, "#{exception} #{exception.message}", cause: exception)
    end

    def self.load(
      driver : Model::Driver,
      store : DriverStore,
      startup : Bool = false,
      module_manager : ModuleManager = ModuleManager.instance,
    ) : Core::Result
      driver_id = driver.id.as(String)
      repository = driver.repository!

      force_recompile = driver.recompile_commit?
      commit = force_recompile.nil? ? driver.commit : force_recompile

      ::Log.with_context(
        driver_id: driver_id,
        name: driver.name,
        file_name: driver.file_name,
        repository_name: repository.folder_name,
        commit: commit,
      ) do
        if !force_recompile && !driver.commit_changed? && (path = store.built?(driver.file_name, commit, repository.branch, repository.uri))
          Log.info { "commit unchanged and driver already compiled" }
          module_manager.reload_modules(driver)
          return Core::Result.new(success: true, path: path)
        end

        Log.info { "force recompiling driver" } if force_recompile
      end

      # If the commit is `head` then the driver must be recompiled at the latest version
      force = !force_recompile.nil? || commit.try(&.upcase) == "HEAD"

      result = store.compile(
        driver.file_name,
        repository.uri,
        commit,
        repository.branch,
        force,
        repository.username,
        repository.decrypt_password
      )

      unless result.success
        Log.error { {message: "failed to compile driver", output: result.output, repository_name: repository.folder_name} }
        return Core::Result.new(output: "failed to compile #{driver.name} from #{repository.folder_name}: #{result.output}")
      end

      Log.info { {
        message:         "compiled driver",
        name:            driver.name,
        executable:      result.name,
        repository_name: repository.folder_name,
        output:          result.output,
      } }

      # (Re)load modules onto the newly compiled driver
      stale_path = module_manager.reload_modules(driver)

      # Remove the stale driver if there was one
      remove_stale_driver(driver_id: driver_id,
        path: stale_path,
      )

      # Bump the commit on the driver post-compilation and module loading
      if (force) && (startup || module_manager.discovery.own_node?(driver_id))
        update_driver_commit(driver: driver, commit: commit, startup: startup)
      end

      result
    end

    # Remove the stale driver binary if there was one
    #
    def self.remove_stale_driver(path : Path?, driver_id : String)
      return unless path
      Log.info { {message: "removing stale driver binary", driver_id: driver_id, path: path.to_s} }
      File.delete(path) if File.exists?(path)
    rescue
      Log.error { {message: "failed to remove stale binary", driver_id: driver_id, path: path.to_s} }
    end

    def self.update_driver_commit(driver : Model::Driver, commit : String, startup : Bool)
      if startup
        # There's a potential for multiple writers on startup, However this is an eventually consistent operation.
        Log.warn { {message: "updating commit on driver during startup", id: driver.id, name: driver.name, commit: commit} }
      end

      driver.update_fields(commit: commit)
      Log.info { {message: "updated commit on driver", id: driver.id, name: driver.name, commit: commit} }
    end

    def self.remove_driver(driver : Model::Driver, store : DriverStore)
      path = store.driver_binary_path(driver.file_name, driver.commit)
      Log.info { {message: "removing driver binary as it got removed from drivers", driver_id: driver.id.as(String), path: path.to_s} }
      remove_stale_driver(path, driver.id.as(String))
    end

    def start_driver_jobs
      DriverIntegrity.start_integrity_checker
      DriverCleanup.start_cleanup
    end

    def start
      super
      @startup = false
      start_driver_jobs
      self
    end

    def stop
      super
      DriverIntegrity.stop_integrity_checker
      DriverCleanup.stop_cleanup
    end
  end
end
