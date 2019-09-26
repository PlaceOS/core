require "engine-rest-api/models/driver"

require "./resource"

module Engine
  class Core::Compilation < Core::Resource(Model::Driver)
    def process_resource(driver) : Bool
      name = driver.name.as(String)
      commit = driver.commit.as(String)

      if compiled?(name, commit)
        true
      else
        repository = driver.repository.as(Model::Repository).name.as(String)
        result = compile_driver(name, repository)
        result[:exit_status] == 0
      end
    end
  end
end
