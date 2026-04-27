require "placeos-models/settings"
require "placeos-resource"

module PlaceOS
  class Core::SettingsUpdate < Resource(Model::Settings)
    private getter module_manager : ModuleManager

    def initialize(@module_manager : ModuleManager = Services.module_manager)
      super()
    end

    def process_resource(action : Resource::Action, resource settings : PlaceOS::Model::Settings) : Resource::Result
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
      module_manager : ModuleManager,
    )
      Log.context.set(settings_id: settings.id)
      result = Result::Success

      # Find each module affected by the Settings change
      dependent_modules(settings).each do |mod|
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

    private def self.dependent_modules(settings : Model::Settings) : Array(Model::Module)
      model_id = settings.parent_id
      model_type = settings.parent_type
      return [] of Model::Module if model_id.nil? || model_type.nil?

      case model_type
      in .module?
        mod = Model::Module.find?(model_id)
        mod ? [mod] : [] of Model::Module
      in .driver?
        Model::Module.by_driver_id(model_id).to_a
      in .control_system?
        Model::Module
          .in_control_system(model_id)
          .select(&.role.logic?)
          .to_a
      in .zone?
        Model::Module
          .in_zone(model_id)
          .select(&.role.logic?)
          .to_a
      end
    end
  end
end
