require "placeos-compiler/compiler"
require "placeos-compiler/helper"
require "placeos-models/driver"
require "placeos-models/repository"
require "placeos-resource"

require "./cloning"
require "./module_manager"

module PlaceOS
  class Core::Compilation < Resource(Model::Driver)
    private getter? startup : Bool = true
    private getter module_manager : ModuleManager

    def initialize(
      @startup : Bool = true,
      bin_dir : String = Compiler.bin_dir,
      drivers_dir : String = Compiler.drivers_dir,
      repository_dir : String = Compiler.repository_dir,
      @module_manager : ModuleManager = ModuleManager.instance
    )
      @compiler_lock = Mutex.new
      buffer_size = System.cpu_count.to_i

      Compiler.bin_dir = bin_dir
      Compiler.drivers_dir = drivers_dir
      Compiler.repository_dir = repository_dir

      super(buffer_size)
    end

    def process_resource(action : Resource::Action, resource : Model::Driver) : Resource::Result
      driver = resource
      case action
      in Resource::Action::Created, Resource::Action::Updated
        success, output = @compiler_lock.synchronize { Compilation.compile_driver(driver, startup?, module_manager) }
        raise Resource::ProcessingError.new(driver.name, output) unless success
        Resource::Result::Success
      in Resource::Action::Deleted
        Result::Skipped
      end
    rescue e
      # Add compilation errors
      raise Resource::ProcessingError.new(resource.name, "#{e} #{e.message}")
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def self.compile_driver(
      driver : Model::Driver,
      startup : Bool = false,
      module_manager : ModuleManager = ModuleManager.instance
    ) : Tuple(Bool, String)
      driver_id = driver.id.as(String)
      repository = driver.repository!

      force_recompile = driver.recompile_commit?
      commit = force_recompile.nil? ? driver.commit : force_recompile

      ::Log.with_context do
        Log.context.set({
          driver_id:       driver_id,
          name:            driver.name,
          file_name:       driver.file_name,
          repository_name: repository.folder_name,
          commit:          commit,
        })

        if !force_recompile && !driver.commit_changed? && Compiler::Helper.compiled?(driver.file_name, commit, driver_id)
          Log.info { "commit unchanged and driver already compiled" }
          Compilation.reload_modules(driver, module_manager)
          return {true, ""}
        end

        Log.info { "force recompiling driver" } if force_recompile
      end

      # If the commit is `head` then the driver must be recompiled at the latest version
      if Compilation.pull?(commit)
        begin
          Cloning.clone_and_install(repository)
        rescue e
          return {false, "failed to pull and install #{repository.folder_name}: #{e.try &.message}"}
        end
      end

      result = Compiler::Helper.compile_driver(driver.file_name, repository.folder_name, commit, id: driver_id)
      success = result[:exit_status] == 0

      unless success
        Log.error { {message: "failed to compile driver", output: result[:output], repository_name: repository.folder_name} }
        return {false, "failed to compile #{driver.name} from #{repository.folder_name}: #{result[:output]}"}
      end

      Log.info { {
        message:         "compiled driver",
        name:            driver.name,
        executable:      result[:executable],
        repository_name: repository.folder_name,
        output:          result[:output],
      } }

      # (Re)load modules onto the newly compiled driver
      stale_path = Compilation.reload_modules(driver, module_manager)

      # Remove the stale driver if there was one
      remove_stale_driver(
        driver_id: driver_id,
        path: stale_path,
      )

      # Bump the commit on the driver post-compilation and module loading
      if (Compilation.pull?(commit) || force_recompile) && (startup || module_manager.discovery.own_node?(driver_id))
        update_driver_commit(driver: driver, commit: result[:version], startup: startup)
      end

      {success, ""}
    end

    # Remove the stale driver binary if there was one
    #
    def self.remove_stale_driver(path : String?, driver_id : String)
      return unless path
      Log.info { {message: "removing stale driver binary", driver_id: driver_id, path: path} }
      File.delete(path) if File.exists?(path)
    rescue
      Log.error { {message: "failed to remove stale binary", driver_id: driver_id, path: path} }
    end

    def self.update_driver_commit(driver : Model::Driver, commit : String, startup : Bool)
      if startup
        # There's a potential for multiple writers on startup, However this is an eventually consistent operation.
        Log.warn { {message: "updating commit on driver during startup", id: driver.id, name: driver.name, commit: commit} }
      end

      driver.update_fields(commit: commit)
      Log.info { {message: "updated commit on driver", id: driver.id, name: driver.name, commit: commit} }
    end

    protected def self.pull?(commit : String?)
      commit.try(&.upcase) == "HEAD"
    end

    # Returns the stale driver path
    #
    protected def self.reload_modules(
      driver : Model::Driver,
      module_manager : ModuleManager
    )
      driver_id = driver.id.as(String)
      # Set when a module_manager found for stale driver
      stale_path = driver.modules.reduce(nil) do |path, mod|
        module_id = mod.id.as(String)

        # Grab the stale driver path, if there is one
        path = module_manager.path_for?(module_id) unless path

        # Save a lookup
        mod.driver = driver

        # Remove the module running on the stale driver
        module_manager.remove_module(mod)

        if module_manager.started?
          # Reload module on new driver binary
          Log.debug { {
            message:   "loading module after compilation",
            module_id: module_id,
            driver_id: driver_id,
            file_name: driver.file_name,
            commit:    driver.commit,
          } }
          module_manager.load_module(mod)
        end

        path
      end

      stale_path || driver.commit_was.try { |commit|
        # Try to create a driver path from what the commit used to be
        Compiler::Helper.driver_binary_path(driver.file_name, commit, driver_id)
      }
    end

    def start
      super
      @startup = false
      self
    end
  end
end
