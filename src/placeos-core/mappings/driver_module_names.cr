require "placeos-resource"
require "placeos-models/driver"

module PlaceOS::Core
  class Mappings::DriverModuleNames < Resource(Model::Driver)
    def process_resource(action : Resource::Action, resource driver : Model::Driver) : Resource::Result
      return Resource::Result::Skipped unless action.updated?

      DriverModuleNames.update_module_names(driver)
    rescue exception
      Log.error(exception: exception) { {message: "while updating `module_name` for driver modules", name: driver.module_name} }
      raise Resource::ProcessingError.new(driver.module_name, exception.message, cause: exception)
    end

    def self.update_module_names(driver : Model::Driver)
      # Only consider `module_name` change events
      return Resource::Result::Skipped unless driver.module_name_changed?

      # Update the `module_name` field across all associated modules
      Model::Module.where(driver_id: driver.id.not_nil!).update_all(name: driver.module_name)
      Resource::Result::Success
    end
  end
end
