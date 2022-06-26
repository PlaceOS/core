require "placeos-driver/storage"
require "placeos-driver/subscriptions"
require "placeos-models/control_system"
require "placeos-models/module"

require "../module_manager"

module PlaceOS::Core
  class Mappings::ControlSystemModules < Resource(Model::ControlSystem)
    private getter? startup : Bool = true
    private getter module_manager : ModuleManager

    def initialize(
      @startup : Bool = true,
      @module_manager : ModuleManager = ModuleManager.instance
    )
      super()
    end

    def process_resource(action : RethinkORM::Changefeed::Event, resource control_system : PlaceOS::Model::ControlSystem) : Resource::Result
      ControlSystemModules.update_mapping(control_system, startup?, module_manager)
    rescue exception
      Log.error(exception: exception) { {message: "while updating mapping for system"} }
      raise Resource::ProcessingError.new(control_system.name, exception.message, cause: exception)
    end

    # Update the mapping for a ControlSystem
    def self.update_mapping(
      system : Model::ControlSystem,
      startup : Bool = false,
      module_manager : ModuleManager = ModuleManager.instance
    ) : Resource::Result
      relevant_node = startup || module_manager.discovery.own_node?(system.id.as(String))
      unless relevant_node
        return update_logic_modules(system, module_manager) > 0 ? Resource::Result::Success : Resource::Result::Skipped
      end

      destroyed = system.destroyed?

      #                      Always load mappings during startup
      #                      |          Remove mappings
      #                      |          |            Initial mappings    Modules have changed
      #                      |          |            |                   |
      mappings_need_update = startup || destroyed || !system.changed? || system.modules_changed?

      if mappings_need_update
        set_mappings(system, nil)
        Log.info { {message: "#{destroyed ? "deleted" : "created"} indirect module mappings", system_id: system.id} }
      end

      updated_logic_modules = update_logic_modules(system, module_manager)

      mappings_need_update || updated_logic_modules > 0 ? Resource::Result::Success : Resource::Result::Skipped
    end

    # Update logic Module children for a ControlSystem
    #
    def self.update_logic_modules(
      system : Model::ControlSystem,
      module_manager : ModuleManager = ModuleManager.instance
    ) : Int32
      return 0 if system.destroyed?

      control_system_id = system.id.as(String)
      total = 0
      updated_modules = Model::Module.logic_for(control_system_id).sum do |mod|
        next 0 unless module_manager.discovery.own_node?(mod.id.as(String))

        total += 1
        begin
          # ensure module has the latest version of the control system model
          mod.control_system = system
          module_manager.refresh_module(mod)
          Log.debug { {message: "#{mod.running_was == false ? "started" : "updated"} system logic module", module_id: mod.id, control_system_id: control_system_id} }
          1
        rescue e
          Log.warn(exception: e) { {message: "failed to refresh logic module for control system", module_id: mod.id, control_system_id: control_system_id} }
          0
        end
      end

      Log.info { {message: "updated system logic modules", control_system_id: control_system_id, total: total, updated: updated_modules} } if updated_modules > 0

      updated_modules
    end

    # Set the module mappings for a ControlSystem
    #
    # Pass module_id and updated_name to overrride a lookup
    def self.set_mappings(
      control_system : Model::ControlSystem,
      mod : Model::Module?
    ) : Hash(String, String)
      system_id = control_system.id.as(String)
      storage = Driver::RedisStorage.new(system_id, "system")

      # Clear out the ControlSystem's mapping
      storage.clear

      # No mappings to set if ControlSystem has been destroyed
      if control_system.destroyed?
        Log.info { {
          message:   "module mappings deleted",
          system_id: control_system.id,
          modules:   control_system.modules,
        } }
        return {} of String => String
      end

      # Construct a hash of resolved module name to ordered module ids
      grouped_modules = control_system.modules.group_by do |id|
        # Save a lookup if a module passed
        (mod && id == mod.id ? mod : Model::Module.find!(id)).resolved_name
      end

      # Index the modules
      mappings = grouped_modules.each_with_object({} of String => String) do |(name, ids), mapping|
        # Indexes start from 1
        ids.each_with_index(offset: 1) do |id, index|
          mapping["#{name}/#{index}"] = id
        end
      end

      # Set the mappings in redis
      mappings.each do |mapping, module_id|
        storage[mapping] = module_id
      end

      Log.info { {message: "module mappings set", system_id: control_system.id, mappings: mappings} }

      # Notify subscribers of a system module ordering change
      Driver::RedisStorage.with_redis(&.publish(Driver::Subscriptions::SYSTEM_ORDER_UPDATE, system_id))

      mappings
    end

    def start
      super
      @startup = false
      self
    end
  end
end
