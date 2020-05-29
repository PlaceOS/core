require "placeos-models/settings"

require "./resource"

module PlaceOS
  class Core::SettingsUpdate < Core::Resource(Model::Settings)
    private getter module_manager : ModuleManager

    def initialize(
      @module_manager : ModuleManager = ModuleManager.instance
    )
      super()
    end

    def process_resource(event) : Resource::Result
      settings = event[:resource]

      # Ignore versions
      if settings.is_version?
        Log.debug { {message: "skipping settings version", settings_id: settings.id, parent_id: settings.settings_id} }
        return Resource::Result::Skipped
      end

      SettingsUpdate.update_modules(settings: settings, module_manager: module_manager)
    rescue e
      model = event[:resource]
      name = "Setting<#{model.id}> for #{model.parent_type}<#{model.parent_id}>"
      # Add update errors
      raise Resource::ProcessingError.new(name, "#{e} #{e.message}")
    end

    def self.update_modules(
      settings : Model::Settings,
      module_manager : ModuleManager
    )
      # Find each module affected by the Settings change
      settings.dependent_modules.each do |mod|
        # Update running modules to the latest settings
        if module_manager.proc_manager_by_module?(mod.id.as(String)) && mod.running
          # Start with updates if the module is running
          module_manager.start_module(mod)
          Log.info { {message: "#{mod.running_was == false ? "started" : "updated"} module with new settings", module_id: mod.id, settings_id: settings.id} }
        end
      end

      Result::Success
    end
  end
end
