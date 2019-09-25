require "engine-rest-api/models/repository"
require "engine-drivers/helper"

require "./resource"

module Engine
  class Core::Cloning < Core::Resource(Model::Repository)
    def process_resource(resource : Model::Repository)
      # TODO: Use engine-drivers/helper methods to clone
    end
  end
end
