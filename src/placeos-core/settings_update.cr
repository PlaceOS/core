require "placeos-models/settings"
require "placeos-resource"

module PlaceOS
  class Core::SettingsUpdate < Resource(Model::Settings)
    private getter module_manager : ModuleManager

    def initialize(@module_manager : ModuleManager = ModuleManager.instance)
      super()
    end

    def process_resource(action : RethinkORM::Changefeed::Event, resource settings : PlaceOS::Model::Settings) : Resource::Result
      # Ignore versions
      if settings.is_version?
        Log.debug { {message: "skipping settings version", settings_id: settings.id, parent_id: settings.settings_id} }
        return Resource::Result::Skipped
      end

      SettingsUpdate.update_modules(settings: settings, module_manager: module_manager)
    rescue exception
      name = "Setting<#{settings.id}> for #{settings.parent_type}<#{settings.parent_id}>"
      raise Resource::ProcessingError.new(name, exception.message, cause: exception)
    end

    def self.update_modules(
      settings : Model::Settings,
      module_manager : ModuleManager
    )
      Log.context.set(settings_id: settings.id)
      result = Result::Success

      # Find each module affected by the Settings change
      settings.dependent_modules.each do |mod|
        begin
          if module_manager.refresh_module(mod)
            Log.info { {message: "#{mod.running_was == false ? "started" : "updated"} module with new settings", module_id: mod.id, settings_id: settings.id} }
          end
        rescue e : ModuleError
          result = Result::Error
          Log.error(exception: e) { {message: "failed to update module's settings", module_id: mod.id} }
        end
      end

      result
    end
  end
end
