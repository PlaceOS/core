require "crystal-engine-api/model/driver"
require "crystal-engine-drivers/helper"

require "./resource"

module Engine
  class Core::Compilation < Core::Resource(Model::Driver)
    def process_resource(resource : Model::Driver)
      # TODO: Use engine-drivers/helper methods to compile
    end
  end
end
