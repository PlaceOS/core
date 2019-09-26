require "engine-rest-api/models/driver"

require "./resource"

module Engine
  class Core::Compilation < Core::Resource(Model::Driver)
    def process_resource(driver) : Bool
      # Check if driver's commit is a part of existing repository
      # Pull if not already present
      # If still not present, log an error
      false
    end
  end
end
