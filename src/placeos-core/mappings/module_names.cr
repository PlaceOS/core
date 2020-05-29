require "driver/storage"
require "driver/subscriptions"
require "placeos-models/control_system"
require "placeos-models/module"

require "../module_manager"
require "./control_system_modules"

module PlaceOS::Core
  class Mappings::ModuleNames < Resource(Model::Module)
    protected getter module_manager : ModuleManager

    def initialize(
      @module_manager : ModuleManager = ModuleManager.instance
    )
      super()
    end

    def process_resource(event) : Resource::Result
      if event[:action] == Action::Updated
        ModuleNames.update_module_mapping(event[:resource], module_manager)
      else
        Resource::Result::Skipped
      end
    rescue e
      mod = event[:resource]
      Log.error(exception: e) { {message: "while updating mapping for module", name: mod.name, custom_name: mod.custom_name} }
      raise Resource::ProcessingError.new(mod.name, "#{e} #{e.message}")
    end

    def self.update_module_mapping(
      mod : Model::Module,
      module_manager : ModuleManager = ModuleManager.instance
    ) : Resource::Result
      module_id = mod.id.as(String)
      # Only consider name change events
      return Resource::Result::Skipped unless mod.custom_name_changed?
      # Only one core updates the mappings
      return Resource::Result::Skipped unless module_manager.discovery.own_node?(module_id)

      # Update mappings for ControlSystems containing the Module
      Model::ControlSystem.using_module(module_id).each do |control_system|
        ControlSystemModules.set_mappings(control_system, mod)
      end

      Resource::Result::Success
    end
  end
end
