require "models/settings"

require "./resource"

module PlaceOS
  class Core::SettingsUpdate < Core::Resource(Model::Settings)
    private getter module_manager : ModuleManager

    def initialize(
      @logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT)),
      @module_manager : ModuleManager = ModuleManager.instance
    )
      super(@logger)
    end

    def process_resource(event) : Resource::Result
      settings = event[:resource]

      # Ignore versions
      if settings.is_version?
        logger.tag_debug("skipping settings version", settings_id: settings.id, parent_id: settings.settings_id)
        return Resource::Result::Skipped
      end

      SettingsUpdate.update_modules(settings: settings, module_manager: module_manager, logger: logger)
    rescue e
      model = event[:resource]
      name = "Setting<#{model.id}> for #{model.parent_type}<#{model.parent_id}>"
      # Add update errors
      raise Resource::ProcessingError.new(name, "#{e} #{e.message}")
    end

    def self.update_modules(
      settings : Model::Settings,
      module_manager : ModuleManager,
      logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT))
    )
      # Find each module affected by the Settings change
      settings.dependent_modules.each do |mod|
        # Update running modules to the latest settings
        if module_manager.proc_manager_by_module?(mod.id.as(String)) && mod.running
          # Start with updates if the module is running
          module_manager.start_module(mod)
          logger.tag_info("#{mod.running_was == false ? "started" : "updated"} module with new settings", module_id: mod.id, settings_id: settings.id)
        end
      end

      Result::Success
    end
  end
end
