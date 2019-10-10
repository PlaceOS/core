require "engine-rest-api/models"

require "./resource"

module ACAEngine
  class Core::Compilation < Core::Resource(Model::Driver)
    def initialize(@logger = Logger.new(STDOUT))
      buffer_size = System.cpu_count.to_i

      super(@logger, buffer_size)
    end

    def process_resource(driver) : Bool
      name = driver.name.as(String)
      commit = driver.commit.as(String)

      if compiled?(name, commit)
        true
      else
        repository = driver.repository.as(Model::Repository).name.as(String)
        result = compile_driver(name, repository)

        success = result[:exit_status] == 0

        errors << {name: repository, reason: result[:output]} unless success

        success
      end
    end
  end
end
