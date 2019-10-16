require "engine-drivers/compiler"
require "engine-models"

require "./resource"

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
      repository = driver.repository.as(Model::Repository).name.as(String)

      # Check commit here, if it's head then we need to update the commit hash
      if commit == "head"
      end

      if compiled?(name, commit)
        true
      else
        result = compile_driver(file_name, repository)

        # TODO: Remove when all build failures caught
        puts result[:output]

        pp! result

        success = result[:exit_status] == 0

        errors << {name: name, reason: result[:output]} unless success

        success
      end
    end
  end
end
