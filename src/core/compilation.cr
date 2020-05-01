require "compiler/drivers/compiler"
require "compiler/drivers/helper"
require "models/driver"
require "models/repository"

require "./cloning"
require "./module_manager"
require "./resource"

module PlaceOS
  class Core::Compilation < Core::Resource(Model::Driver)
    private getter? startup : Bool = true
    private getter module_manager : ModuleManager

    def initialize(
      @startup : Bool = true,
      bin_dir : String = Drivers::Compiler.bin_dir,
      drivers_dir : String = Drivers::Compiler.drivers_dir,
      repository_dir : String = Drivers::Compiler.repository_dir,
      @module_manager : ModuleManager = ModuleManager.instance
    )
      buffer_size = System.cpu_count.to_i
      Drivers::Compiler.bin_dir = bin_dir
      Drivers::Compiler.drivers_dir = drivers_dir
      Drivers::Compiler.repository_dir = repository_dir

      super(buffer_size)
    end

    def process_resource(event) : Resource::Result
      driver = event[:resource]
      case event[:action]
      when Action::Created, Action::Updated
        success, output = Compilation.compile_driver(driver, startup?, module_manager)
        raise Resource::ProcessingError.new(driver.name, output) unless success
        Result::Success
      when Action::Deleted
        Result::Skipped
      end.as(Result)
    rescue e
      # Add compilation errors
      raise Resource::ProcessingError.new(event[:resource].name, "#{e} #{e.message}")
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def self.compile_driver(
      driver : Model::Driver,
      startup : Bool = false,
      module_manager : ModuleManager = ModuleManager.instance
    ) : Tuple(Bool, String)
      commit = driver.commit.as(String)
      driver_id = driver.id.as(String)
      file_name = driver.file_name.as(String)
      name = driver.name.as(String)

      repository = driver.repository.as(Model::Repository)
      repository_name = repository.folder_name.as(String)

      force_recompile = driver.recompile_commit?
      commit = force_recompile unless force_recompile.nil?

      ::Log.with_context do
        Log.context.set({
          driver_id:       driver_id,
          name:            name,
          file_name:       file_name,
          repository_name: repository_name,
          commit:          commit,
        })

        if !force_recompile && !driver.commit_changed? && Drivers::Helper.compiled?(file_name, commit, driver_id)
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
          return {false, "failed to pull and install #{repository_name}: #{e.try &.message}"}
        end
      end

      result = Drivers::Helper.compile_driver(file_name, repository_name, commit, id: driver_id)
      success = result[:exit_status] == 0

      unless success
        Log.error { {message: "failed to compile driver", output: result[:output], repository_name: repository_name} }
        return {false, "failed to compile #{name} from #{repository_name}: #{result[:output]}"}
      end

      Log.info { {
        message:         "compiled driver",
        name:            name,
        executable:      result[:executable],
        repository_name: repository_name,
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
        Drivers::Helper.driver_binary_path(driver.file_name.as(String), commit, driver_id)
      }
    end

    def start
      super
      @startup = false
      self
    end
  end
end
