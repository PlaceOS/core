require "action-controller/logger"
require "driver/storage"
require "driver/subscriptions"
require "models/control_system"
require "models/module"

require "./module_manager"

module PlaceOS
  class Core::Mappings < Core::Resource(Model::ControlSystem)
    private getter? startup : Bool = true

    def initialize(
      @logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT)),
      @startup : Bool = true
    )
      super(@logger)
    end

    def process_resource(event) : Resource::Result
      Mappings.update_mapping(event[:resource], startup?, logger)
    rescue e
      message = e.try(&.message) || ""
      logger.tag_error("while updating mapping for system", error: message)
      errors << {name: event[:resource].name.as(String), reason: message}

      Resource::Result::Error
    end

    def self.update_mapping(
      system : Model::ControlSystem,
      startup : Bool = false,
      logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT))
    ) : Resource::Result
      # NOTE the module's custom name is not used for the key
      system_id = system.id.as(String)
      module_ids = system.modules.as(Array(String))

      destroyed = system.destroyed?

      # Always load mappings during startup
      relevant_node = startup || ModuleManager.instance.discovery.own_node?(system_id)

      if relevant_node
        storage = Driver::Storage.new(system_id, "system")

        if destroyed
          storage.clear
        else
          # Construct a hash of module name to module ids (in-order)
          keys = {} of String => Array(String)
          module_ids.each do |id|
            # Extract module name
            model = Model::Module.find!(id)
            name = model.custom_name || model.name.as(String)
            name = model.name.as(String) if name.empty?

            # Save ordering
            modules = keys[name]? || [] of String
            modules << id
            keys[name] = modules
          end

          older = storage.to_h
          current = {} of String => String

          # Index the modules
          keys.each do |name, ids|
            ids.each_with_index do |id, index|
              # Indexes start from 1
              key = "#{name}/#{index + 1}"
              storage[key] = id
              current[key] = id
            end
          end

          remove = older.keys - current.keys
          remove.each { |key| storage.delete(key) }

          # Notify subscribers of a system module ordering change
          return Resource::Result::Skipped unless remove.size > 0 || older != current
          Driver::Storage.redis_pool.publish(Driver::Subscriptions::SYSTEM_ORDER_UPDATE, system_id)
        end

        logger.tag_info("#{destroyed ? "deleted" : "created"} indirect module mappings", system_id: system_id)

        Resource::Result::Success
      else
        Resource::Result::Skipped
      end
    end

    def start
      super
      @startup = false
      self
    end
  end
end
