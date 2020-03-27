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

    def initialize(
      @logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT)),
      @startup : Bool = true,
      bin_dir : String = Drivers::Compiler.bin_dir,
      drivers_dir : String = Drivers::Compiler.drivers_dir,
      repository_dir : String = Drivers::Compiler.repository_dir
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
        success, output = Compilation.compile_driver(driver, startup?, logger)
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
      logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT))
    ) : Tuple(Bool, String)
      commit = driver.commit.as(String)
      driver_id = driver.id.as(String)
      file_name = driver.file_name.as(String)
      name = driver.name.as(String)

      repository = driver.repository.as(Model::Repository)
      repository_name = repository.folder_name.as(String)

      update_commit = false
      # If the commit is `head` then the driver must be recompiled.
      if commit == "head"
        begin
          Cloning.clone_and_install(repository)
          update_commit = ModuleManager.instance.discovery.own_node?(driver_id) || startup
        rescue e
          return {false, "failed to pull and install #{repository_name}: #{e.try &.message}"}
        end
      elsif Drivers::Helper.compiled?(file_name, commit)
        logger.tag_info("driver already compiled", name: name, repository_name: repository_name, commit: commit)
        return {true, ""}
      end

      result = Drivers::Helper.compile_driver(file_name, repository_name)
      success = result[:exit_status] == 0

      if success
        logger.tag_info("compiled driver", name: name, repository_name: repository_name, output: result[:output])
        module_manager = ModuleManager.instance

        # Set when a module_manager found for stale driver
        driver_path = nil

        driver.modules.each do |mod|
          module_id = mod.id.as(String)

          # Remove the module running on the stale driver
          driver_path = module_manager.path_for?(module_id)
          module_manager.remove_module(mod)

          if module_manager.started?
            # Reload module on new driver binary
            logger.tag_debug("reloading module after compilation", module_id: module_id, path: driver_path, driver_id: driver_id)
            module_manager.load_module(mod)
          end
        end

        # Remove the stale driver if there is one and there are no more modules running on it.
        if driver_path && module_manager.proc_manager_by_driver?(driver_path)
          remove_stale_driver(driver_path, driver_id, logger)
        end

        if update_commit
          # Bump the commit on the driver post-compilation and module loading
          update_driver_commit(driver: driver, commit: result[:version], startup: startup, logger: logger)
        end
      else
        logger.tag_error("failed to compile driver", name: {name}, repository_name: repository_name, output: result[:output])
      end

      {success, result[:output]}
    end

    def self.remove_stale_driver(path : String, driver_id : String, logger)
      logger.tag_info("removing stale driver binary", path: path, driver_id: driver_id)
      begin
        File.delete(path)
      rescue
        logger.tag_error("failed to remove stale driver binary", path: path, driver_id: driver_id)
      end
    end

    def self.update_driver_commit(driver : Model::Driver, commit : String, startup : Bool, logger)
      if startup
        # There's a potential for multiple writers on startup, However this is an eventually consistent operation.
        logger.tag_warn("updating commit on driver during startup", name: driver.name, id: driver.id, commit: commit)
      end

      driver.update_fields(commit: commit)
      logger.tag_info("updated commit on driver", name: driver.name, id: driver.id, commit: commit)
    end

    def start
      super
      @startup = false
      self
    end
  end
end
