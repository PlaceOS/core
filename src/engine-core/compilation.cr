require "action-controller/logger"
require "engine-drivers/compiler"
require "engine-models/driver"
require "engine-models/repository"

require "./cloning"
require "./module_manager"
require "./resource"

module ACAEngine
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
      repository_name = repository.name.as(String)

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
      else
        logger.tag_error("failed to compile driver", name: {name}, repository_name: repository_name, output: result[:output])
      end

      if update_commit && success
        commit = result[:version]

        if startup
          # There's a potential for multiple writers on startup,
          # However this is an eventually consistent operation.
          logger.tag_warn("updating commit on driver during startup", name: name, id: driver.id, commit: commit)
        end

        driver.update_fields(commit: commit)
      end

      {success, result[:output]}
    end

    def process_resource(driver) : Resource::Result
      success, output = Compilation.compile_driver(driver, startup?, logger)
      errors << {name: driver.name.as(String), reason: output} unless success
      success ? Resource::Result::Success : Resource::Result::Error
    end

    def start
      super
      @startup = false
      self
    end
  end
end
