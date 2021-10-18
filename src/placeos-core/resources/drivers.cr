require "placeos-models"
require "placeos-models/driver"
require "placeos-models/repository"
require "placeos-resource"

require "placeos-build/client"
require "placeos-build/driver_store/filesystem"

require "./modules"

module PlaceOS::Core::Resources
  # # Drivers
  #
  # ## Start
  # - new driver
  # - load any waiting modules
  #
  # ## Create
  # - new driver
  # - load any waiting modules
  #
  # ## Update
  # - remove current driver
  # - stop modules
  # - new driver
  # - "reload" modules
  #
  # ## Delete
  # - stop modules
  # - remove current driver
  class Drivers < Resource(Model::Driver)
    private getter module_manager : Resources::Modules

    getter binary_store : Build::Filesystem

    # Concurrent processes
    private BUFFER_SIZE = 4

    def initialize(
      @binary_store : Build::Filesystem = Build::Filesystem.new(Path["./bin/drivers"].expand.to_s),
      @module_manager : Resources::Modules = Resources::Modules.instance
    )
      super(BUFFER_SIZE)
    end

    def process_resource(action : Resource::Action, resource driver : Model::Driver) : Resource::Result
      case action
      in .created?, .updated?
        unless Drivers.load(driver, binary_store, module_manager)
          raise Resource::ProcessingError.new(driver.name, driver.compilation_output)
        end
        Resource::Result::Success
      in .deleted?
        # Unload
        Result::Skipped
      end
    rescue exception
      raise Resource::ProcessingError.new(driver.name, "#{exception} #{exception.message}", cause: exception)
    end

    # TODO:
    # - Delete driver from the binary store on delete
    # - Ensure reloads are correct
    def self.load(
      driver : Model::Driver,
      binary_store : Build::Filesystem,
      module_manager : Resources::Modules = Resources::Modules.instance
    )
      driver_id = driver.id.as(String)
      repository = driver.repository!
      commit = driver.commit
      Log.context.set(
        driver_id: driver_id,
        name: driver.name,
        file_name: driver.file_name,
        repository_name: repository.folder_name,
        commit: commit,
      )

      fetch_driver(
        driver: driver,
        binary_store: binary_store,
        own_node: module_manager.discovery.own_node?(driver_id),
      ) do
        reload_modules(driver, module_manager)
      end
    end

    # (Re)load modules onto the compiled driver
    def self.reload_modules(driver, module_manager)
      # TODO: Ensure that drivers are reloaded _for_ the driver only
      #       May need to associate driver manager with a `driver_id`
      module_manager.reload_modules(driver)

      # TODO: Use a LRU cache for drivers not in use
    end

    def self.fetch_driver(
      driver : Model::Driver,
      binary_store : Build::Filesystem,
      own_node : Bool,
      request_id : String? = nil
    ) : Bool
      # Check binary store first
      # TODO: Add crystal version to driver model
      unless binary_store.query(driver.file_name, commit: driver.commit).empty?
        yield
        return true
      end

      result = Build::Client.client(BUILD_URI) do |client|
        client.compile(
          file: driver.file_name,
          url: driver.repository!.uri,
          commit: driver.commit,
          username: driver.repository!.username,
          password: driver.repository!.decrypt_password,
          request_id: request_id
        ) do |key, driver_io|
          # Write the compiled driver to the binary store
          binary_store.write(key, driver_io)
        end
      end

      # Perform updates to modules before updating data
      yield if result.success?

      if own_node
        case result
        in Build::Compilation::Success
          driver.compilation_output = nil unless driver.compilation_output.nil?
          driver.commit = result.executable.commit unless driver.commit == result.executable.commit
          driver.save!
        in Build::Compilation::NotFound
          output = "Driver #{driver.file_name} not found in #{driver.repository!.uri} at #{driver.commit}"
          driver.update_fields(compilation_output: output) unless driver.compilation_output == output
          driver.compilation_output = output
        in Build::Compilation::Failure
          driver.update_fields(compilation_output: result.error) unless driver.compilation_output == result.error
          driver.compilation_output = result.error
        end
      end

      result.success?
    end

    def start
      super
      self
    end
  end
end
