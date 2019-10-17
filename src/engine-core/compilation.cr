require "engine-drivers/compiler"
require "engine-models"

require "./resource"
require "./cloning"

module ACAEngine
  class Core::Compilation < Core::Resource(Model::Driver)
    def initialize(
      @logger = Logger.new(STDOUT),
      # NOTE: Mainly for testing purposes
      repository_dir = ACAEngine::Drivers::Compiler.repository_dir,
      drivers_dir = ACAEngine::Drivers::Compiler.drivers_dir,
      bin_dir = ACAEngine::Drivers::Compiler.bin_dir
    )
      buffer_size = System.cpu_count.to_i
      ACAEngine::Drivers::Compiler.repository_dir = repository_dir
      ACAEngine::Drivers::Compiler.drivers_dir = drivers_dir
      ACAEngine::Drivers::Compiler.bin_dir = bin_dir

      super(@logger, buffer_size)
    end

    def process_resource(driver) : Bool
      commit = driver.commit.as(String)
      file_name = driver.file_name.as(String)
      name = driver.name.as(String)
      repository = driver.repository.as(Model::Repository)
      repository_name = repository.name.as(String)

      # If the commit is `head` then the driver must be recompiled.
      if commit == "head"
        begin
          Cloning.clone_and_install(repository)
        rescue e
          errors << {name: name, reason: "failed to pull and install #{repository_name}: #{e.try &.message}"}
          return false
        end

        commit = ACAEngine::Drivers::Compiler.normalize_commit(commit, file_name, repository_name)
        driver.update_fields(commit: commit)
      elsif compiled?(name, commit)
        return true
      end

      result = compile_driver(file_name, repository_name)
      logger.info("compiled driver: name=#{file_name} repository_name=#{repository_name} output=#{result[:output]}")
      success = result[:exit_status] == 0
      errors << {name: name, reason: result[:output]} unless success

      success
    end
  end
end
