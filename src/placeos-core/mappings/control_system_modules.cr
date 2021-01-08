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

    def process_resource(action : RethinkORM::Changefeed::Event, resource : PlaceOS::Model::ControlSystem) : Resource::Result
      sys = resource
      ControlSystemModules.update_mapping(sys, startup?, module_manager)
    rescue e
      Log.error(exception: e) { {message: "while updating mapping for system"} }
      raise Resource::ProcessingError.new(resource.name, "#{e} #{e.message}")
    end

    # Update the mappingg for a ControlSystem
    def self.update_mapping(
      system : Model::ControlSystem,
      startup : Bool = false,
      module_manager : ModuleManager = ModuleManager.instance
    ) : Resource::Result
      destroyed = system.destroyed?
      relevant_node = startup || module_manager.discovery.own_node?(system.id.as(String))

      return Resource::Result::Skipped unless relevant_node

      #                      Always load mappings during startup
      #                      |          Remove mappings
      #                      |          |            Initial mappings    Modules have changed
      #                      |          |            |                   |
      mappings_need_update = startup || destroyed || !system.changed? || system.modules_changed?

      updated_logic_modules = update_logic_modules(system, module_manager)

      if mappings_need_update
        set_mappings(system, nil)
        Log.info { {message: "#{destroyed ? "deleted" : "created"} indirect module mappings", system_id: system.id} }
      end

      mappings_need_update || updated_logic_modules ? Resource::Result::Success : Resource::Result::Skipped
    end

    # Update logic Module children for a ControlSystem
    #
    def self.update_logic_modules(
      system : Model::ControlSystem,
      module_manager : ModuleManager = ModuleManager.instance
    )
      return false if system.destroyed?

      control_system_id = system.id.as(String)
      updated = Model::Module.logic_for(control_system_id).reduce(0) do |updates, mod|
        if module_manager.refresh_module(mod)
          Log.info { {message: "#{mod.running_was == false ? "started" : "updated"} system logic module", module_id: mod.id, control_system_id: control_system_id} }
          updates + 1
        else
          updates
        end
      end

      updated_modules = updated > 0

      Log.info { {message: "configured #{updated} control_system logic modules", control_system_id: control_system_id} } if updated_modules

      updated_modules
    end

    # Set the module mappings for a ControlSystem
    #
    # Pass module_id and updated_name to overrride a lookup
    def self.set_mappings(
      control_system : Model::ControlSystem,
      mod : Model::Module?
    )
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
        return
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
    end

    def start
      super
      @startup = false
      self
    end
  end
end
