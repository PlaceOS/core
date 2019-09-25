require "engine-rest-api/models/driver"
require "engine-drivers/helper"

require "./resource"

module Engine
  class Core::Compilation < Core::Resource(Model::Driver)
    def process_resource(resource : Model::Driver)
      # TODO: Use engine-drivers/helper methods to compile
    end
  end
end
