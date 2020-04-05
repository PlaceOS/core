require "action-controller/logger"
require "drivers/compiler"
require "drivers/helper"
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
      @logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT)),
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

      super(@logger, buffer_size)
    end

    def process_resource(event) : Resource::Result
      driver = event[:resource]
      case event[:action]
      when Action::Created, Action::Updated
        success, output = Compilation.compile_driver(driver, startup?, module_manager, logger)
        errors << {name: driver.name.as(String), reason: output} unless success
        success ? Result::Success : Result::Error
      when Action::Deleted
        Result::Skipped
      end.as(Result)
    rescue e
      # Add compilation errors
      errors << {name: event[:resource].name.as(String), reason: e.try &.message || ""}
      Result::Error
    end

    def self.compile_driver(
      driver : Model::Driver,
      startup : Bool = false,
      module_manager : ModuleManager = ModuleManager.instance,
      logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT))
    ) : Tuple(Bool, String)
      commit = driver.commit.as(String)
      driver_id = driver.id.as(String)
      file_name = driver.file_name.as(String)
      name = driver.name.as(String)

      repository = driver.repository.as(Model::Repository)
      repository_name = repository.folder_name.as(String)

      if !driver.commit_changed? && Drivers::Helper.compiled?(file_name, commit, driver_id)
        logger.tag_info(
          message: "commit unchanged and driver already compiled",
          name: name,
          file_name: file_name,
          commit: commit,
          driver_id: driver_id,
          repository_name: repository_name,
        )

        Compilation.reload_modules(driver, module_manager, logger)
        return {true, ""}
      end

      # If the commit is `head` then the driver must be recompiled at the latest version
      if Compilation.pull?(commit)
        begin
          Cloning.clone_and_install(repository)
        rescue e
          return {false, "failed to pull and install #{repository_name}: #{e.try &.message}"}
        end
      end

      result = Drivers::Helper.compile_driver(file_name, repository_name, id: driver_id)
      success = result[:exit_status] == 0

      unless success
        logger.tag_error("failed to compile driver: #{result[:output]}", repository_name: repository_name)
        return {false, "failed to compile #{name} from #{repository_name}: #{result[:output]}"}
      end

      logger.tag_info(
        message: "compiled driver",
        name: name,
        executable: result[:executable],
        repository_name: repository_name,
        output: result[:output]
      )

      # (Re)load modules onto the newly compiled driver
      stale_path = Compilation.reload_modules(driver, module_manager, logger)

      # Remove the stale driver if there was one
      remove_stale_driver(
        path: stale_path,
        driver_id: driver_id,
        logger: logger
      )

      # Bump the commit on the driver post-compilation and module loading
      if Compilation.pull?(commit) && (startup || module_manager.discovery.own_node?(driver_id))
        update_driver_commit(driver: driver, commit: result[:version], startup: startup, logger: logger)
      end

      {success, ""}
    end

    # Remove the stale driver binary if there was one
    #
    def self.remove_stale_driver(path : String?, driver_id : String, logger)
      return unless path
      logger.tag_info("removing stale driver binary", path: path, driver_id: driver_id)
      File.delete(path) if File.exists?(path)
    rescue
      logger.tag_error("failed to remove stale driver binary", path: path, driver_id: driver_id)
    end

    def self.update_driver_commit(driver : Model::Driver, commit : String, startup : Bool, logger)
      if startup
        # There's a potential for multiple writers on startup, However this is an eventually consistent operation.
        logger.tag_warn("updating commit on driver during startup", name: driver.name, id: driver.id, commit: commit)
      end

      driver.update_fields(commit: commit)
      logger.tag_info("updated commit on driver", name: driver.name, id: driver.id, commit: commit)
    end

    protected def self.pull?(commit : String?)
      commit == "head"
    end

    # Returns the stale driver path
    #
    protected def self.reload_modules(
      driver : Model::Driver,
      module_manager : ModuleManager,
      logger
    )
      driver_id = driver.id.as(String)

      # Set when a module_manager found for stale driver
      stale_path = driver.modules.reduce(nil) do |path, mod|
        module_id = mod.id.as(String)

        # Grab the stale driver path, if there is one
        path = module_manager.path_for?(module_id) unless path

        # Remove the module running on the stale driver
        module_manager.remove_module(mod)

        if module_manager.started?
          # Reload module on new driver binary
          logger.tag_debug(
            message: "loading module after compilation",
            module_id: module_id,
            file_name: driver.file_name,
            commit: driver.commit,
            driver_id: driver_id,
          )
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
