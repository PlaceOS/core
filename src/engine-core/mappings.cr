require "action-controller/logger"
require "engine-driver/storage"
require "engine-models"

require "./module_manager"

module ACAEngine
  # TODO resource manager for removing module mappings on module deletes
  class Core::Mappings < Core::Resource(Model::ControlSystem)
    private getter? startup : Bool = true

    def initialize(
      @logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT)),
      @startup : Bool = true
    )
      super(@logger)
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
      needs_update = startup || destroyed || system.modules_changed?

      if relevant_node && needs_update
        storage = Driver::Storage.new(system_id, "system")
        # generate hash keys
        keys = module_ids.map_with_index do |id, index|
          name = Model::Module.find(id).try &.custom_name
          "#{name}\x02#{index}" if name
        end

        module_ids.each_with_index do |id, index|
          unless (key = keys[index])
            logger.tag_warn("module not found while setting indirect mapping in redis", module_id: id, index: index)
            next
          end
          # Remove the mapping if system destroyed
          storage[key] = destroyed ? nil : id
        end

        logger.tag_info("#{destroyed ? "deleted" : "created"} indirect module mappings", system_id: system_id)
        Resource::Result::Success
      else
        Resource::Result::Skipped
      end
    end

    def process_resource(system) : Resource::Result
      Mappings.update_mapping(system, startup?, logger)
    rescue e
      message = e.try(&.message) || ""
      logger.tag_error("while updating mapping for system", error: message)
      errors << {name: system.name.as(String), reason: message}

      Resource::Result::Error
    end

    def start
      super
      @startup = false
      self
    end
  end
end
