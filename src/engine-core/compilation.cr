require "engine-drivers/compiler"
require "engine-models"
require "logger"

require "./cloning"
require "./module_manager"
require "./resource"

module ACAEngine
  class Core::Compilation < Core::Resource(Model::Driver)
    private property startup : Bool = true

    def initialize(
      @logger = Logger.new(STDOUT),
      # NOTE: Mainly for testing purposes
      bin_dir = ACAEngine::Drivers::Compiler.bin_dir,
      drivers_dir = ACAEngine::Drivers::Compiler.drivers_dir,
      repository_dir = ACAEngine::Drivers::Compiler.repository_dir
    )
      buffer_size = System.cpu_count.to_i
      ACAEngine::Drivers::Compiler.bin_dir = bin_dir
      ACAEngine::Drivers::Compiler.drivers_dir = drivers_dir
      ACAEngine::Drivers::Compiler.repository_dir = repository_dir

      super(@logger, buffer_size)

      @startup = false
    end

    def self.compile_driver(
      driver : Model::Driver,
      startup : Bool = false,
      logger : Logger = Logger.new(STDOUT)
    ) : NamedTuple(exit_status: Int32, output: String)
      commit = driver.commit.as(String)
      file_name = driver.file_name.as(String)
      name = driver.name.as(String)

      repository = driver.repository.as(Model::Repository)
      repository_name = repository.name.as(String)

      update_commit = false

      # If the commit is `head` then the driver must be recompiled.
      if commit == "head"
        begin
          Cloning.clone_and_install(repository)
        rescue e
          return {exit_status: 1, output: "failed to pull and install #{repository_name}: #{e.try &.message}"}
        end

        commit = ACAEngine::Drivers::Compiler.normalize_commit(commit, file_name, repository_name)

        # Only update the commit on the driver model if it maps to the current node through consistent hashing
        update_commit = ModuleManager.instance.discovery.own_node?(driver.id.as(String))

        # There's a potential for multiple writers on startup,
        # However this is an eventually consistent operation.
        if update_commit && startup
          logger.warn("updating commit on driver during startup: name=#{name} driver_id=#{driver.id}")
        end
      elsif ACAEngine::Drivers::Helper.compiled?(name, commit)
        return {exit_status: 0, output: ""}
      end

      result = ACAEngine::Drivers::Helper.compile_driver(file_name, repository_name)
      logger.info("compiled driver: name=#{file_name} repository_name=#{repository_name} output=#{result[:output]}")

      if update_commit && result[:exit_status] == 0
        driver.update_fields(commit: commit)
      end

      {exit_status: result[:exit_status], output: result[:output]}
    end

    def process_resource(driver) : Bool
      result = Compilation.compile_driver(driver, startup, logger)
      success = result[:exit_status] == 0
      errors << {name: driver.name.as(String), reason: result[:output]} unless success
      success
    end
  end
end
