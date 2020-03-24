require "action-controller/logger"
require "driver/storage"
require "driver/subscriptions"
require "models/control_system"
require "models/module"

require "../module_manager"

module PlaceOS::Core
  class Mappings::ControlSystemModules < Resource(Model::ControlSystem)
    private getter? startup : Bool = true

    def initialize(
      @logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT)),
      @startup : Bool = true
    )
      super(@logger)
    end

    def process_resource(event) : Resource::Result
      ControlSystemModules.update_mapping(event[:resource], startup?, logger)
    rescue e
      message = e.try(&.message) || ""
      logger.tag_error("while updating mapping for system", error: message)
      errors << {name: event[:resource].name.as(String), reason: message}

      Resource::Result::Error
    end

    # Update the mappingg for a ControlSystem
    def self.update_mapping(
      system : Model::ControlSystem,
      startup : Bool = false,
      logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT))
    ) : Resource::Result
      destroyed = system.destroyed?
      relevant_node = startup || ModuleManager.instance.discovery.own_node?(system.id.as(String))
      # Always load mappings during startup
      needs_update = startup || destroyed || system.modules_changed?

      return Resource::Result::Skipped unless relevant_node && needs_update

      set_mappings(system)
      logger.tag_info("#{destroyed ? "deleted" : "created"} indirect module mappings", system_id: system.id)

      Resource::Result::Success
    end

    # Set the module mappings for a ControlSystem
    #
    # Pass module_id and updated_name to overrride a lookup
    def self.set_mappings(
      control_system : Model::ControlSystem,
      mod : Model::Module? = nil
    )
      system_id = control_system.id.as(String)
      storage = Driver::Storage.new(system_id, "system")

      # Clear out the ControlSystem's mapping
      storage.clear

      # No mappings to set if ControlSystem has been destroyed
      return if control_system.destroyed?

      module_ids = control_system.modules.as(Array(String))

      # Construct a hash of resolved module name to ordered module ids
      grouped_modules = module_ids.group_by do |id|
        # Save a lookup if id and name passed
        (mod && id == mod.id ? mod : Model::Module.find!(id)).resolved_name.as(String)
      end

      # Index the modules
      grouped_modules.each do |name, ids|
        # Indexes start from 1
        ids.each_with_index(offset: 1) do |id, index|
          storage["#{name}/#{index}"] = id
        end
      end

      # Notify subscribers of a system module ordering change
      Driver::Storage.redis_pool.publish(Driver::Subscriptions::SYSTEM_ORDER_UPDATE, system_id)
    end

    def start
      super
      @startup = false
      self
    end
  end
end
