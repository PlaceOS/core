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
      module_id : String? = nil,
      module_name : String? = nil
    )
      system_id = control_system.id.as(String)
      storage = Driver::Storage.new(system_id, "system")

      # Clear out the ControlSystem's mapping
      storage.clear

      # No mappings to set if ControlSystem has been destroyed
      return if control_system.destroyed?

      module_ids = control_system.modules.as(Array(String))

      # Construct a hash of module name to ordered module ids
      grouped_modules = module_ids.each_with_object({} of String => Array(String)) do |id, keys|
        # Extract the Module name
        name = if id == module_id && module_name
                 # Save a lookup if id and name passed
                 module_name
               else
                 mapping_name(Model::Module.find!(id))
               end

        # Save ordering
        modules = keys[name]? || [] of String
        modules << id
        keys[name] = modules
      end

      # Index the modules
      grouped_modules.each do |name, ids|
        ids.each_with_index do |id, index|
          # Indexes start from 1
          storage["#{name}/#{index + 1}"] = id
        end
      end

      # Notify subscribers of a system module ordering change
      Driver::Storage.redis_pool.publish(Driver::Subscriptions::SYSTEM_ORDER_UPDATE, system_id)
    end

    # Extract the mapping name from a Module.
    #
    # Nil/empty custom_name indicates driver's module_name used
    def self.mapping_name(mod : Model::Module)
      custom_name = mod.custom_name
      if custom_name.nil? || custom_name.empty?
        mod.name.as(String)
      else
        custom_name
      end
    end

    def start
      super
      @startup = false
      self
    end
  end
end
