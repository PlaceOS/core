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

      #              Always load mappings during startup
      #              |          Remove mappings
      #              |          |            Initial mappings    Modules have changed
      #              |          |            |                   |
      needs_update = startup || destroyed || !system.changed? || system.modules_changed?

      return Resource::Result::Skipped unless relevant_node && needs_update

      set_mappings(system, nil)
      Log.info { {message: "#{destroyed ? "deleted" : "created"} indirect module mappings", system_id: system.id} }

      Resource::Result::Success
    end

    # Set the module mappings for a ControlSystem
    #
    # Pass module_id and updated_name to overrride a lookup
    def self.set_mappings(
      control_system : Model::ControlSystem,
      mod : Model::Module?
    )
      system_id = control_system.id.as(String)
      storage = Driver::Storage.new(system_id, "system")

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
      storage.redis.publish(Driver::Subscriptions::SYSTEM_ORDER_UPDATE, system_id)
    end

    def start
      super
      @startup = false
      self
    end
  end
end
