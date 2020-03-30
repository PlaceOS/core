require "models/settings"

require "./resource"

module PlaceOS
  class Core::SettingsUpdate < Core::Resource(Model::Settings)
    def process_resource(event) : Resource::Result
      settings = event[:resource]

      # Ignore versions
      return Resource::Result::Skipped if settings.is_version?

      SettingsUpdate.update_modules(settings: settings, logger: logger)
    rescue e
      model = event[:resource]
      name = "Setting<#{model.id}> for #{model.parent_type}<#{model.parent_id}>"
      # Add update errors
      errors << {name: name, reason: e.try &.message || ""}

      Result::Error
    end

    def self.update_modules(
      settings : Model::Settings,
      logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT))
    )
      module_manager = ModuleManager.instance

      # Find each module affected by the Settings change
      settings.dependent_modules.each do |mod|
        # Update running modules to the latest settings
        if module_manager.proc_manager_by_module?(mod.id.as(String)) && mod.running
          # Start with updates if the module is running
          module_manager.start_module(mod)
        end
      end

      Result::Success
    end
  end
end
