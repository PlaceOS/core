require "logger"
require "hound-dog"
require "habitat"
require "engine-driver/protocol/management"
require "engine-rest-api/models"

module Engine
  class Core::ModuleManager
    getter discovery : HoundDog::Discovery
    getter logger : Logger = settings.logger

    Habitat.create do
      setting ip : String = ENV["CORE_HOST"]? || "localhost"
      setting port : UInt16 = (ENV["CORE_PORT"]? || 3000).to_u16
      setting logger : Logger = Logger.new(STDOUT)
    end

    # # Ready-state logic sketch
    # increment_string = ->(var : String) { (var.to_i + 1).to_s }
    #
    # value = "0" unless (value = client.get(key))
    #
    # # Attempt to increment the nodes in the cluster state
    # # This will require a slight change to the etcd library (regarding return type)
    # value, success = client.compare_and_swap(key, value, increment_string.call(value)) # result => {String, Bool}
    #
    # until success
    #     value, success = client.compare_and_swap(key, value, increment_string.call(value))
    # end
    #
    # # Set up a watch feed on the cluster state.
    # # Once the cluster state for ready nodes is equal to the cluster, continue.
    # # The watch feed occurs separately,
    # # - Once the ready state is reached, it continues operations.
    # # - If the state is inconsistent, it triggers the above block (stabilize, then increment)
    # # - Flow is blocked by the watch feed

    # From environment
    @@instance = new(
      ip: settings.ip,
      port: settings.port,
      logger: settings.logger,
    )

    # Mapping from module_id to protocol manager
    @@module_proc_managers = {} of String => EngineDriver::Protocol::Management
    # Mapping from driver path to protocol manager
    @@driver_proc_managers = {} of String => EngineDriver::Protocol::Management

    # Once registered, run through all the modules, consistent hashing to determine what modules need to be loaded
    # Start the driver processes as required.
    # Launch the modules on those processes etc
    # Once all the modules are running. Mark in etcd that load is complete.
    def initialize(ip : String, port : UInt16, @logger = Logger.new(STDOUT))
      @discovery = HoundDog::Discovery.new(service: "core", ip: ip, port: port)
    end

    # Class to be used as a singleton
    def self.instance : ModuleManager
      @@instance
    end

    def watch_modules
      Model::Module.changes.each do |change|
        mod = change[:value]
        mod_id = mod.id.as(String)
        if change[:event] == RethinkORM::Changefeed::Event::Type::Deleted
          remove_module(mod) if manager_by_module_id(mod_id)
        else
          if mod.running_changed?
            # Running state of the module changed
            mod.running ? start_module(mod_id) : stop_module(mod_id)
          else
            # Load/Reload the module
            load_module(mod)
          end
        end
      end
    end

    # The number of drivers loaded on current node
    def running_drivers
      @@driver_proc_managers.size
    end

    # The number of module processes on current node
    def running_modules
      @@module_proc_managers.size
    end

    def manager_by_module_id(mod_id : String) : EngineDriver::Protocol::Management?
      @@module_proc_managers[mod_id]?
    end

    def manager_by_driver_path(path : String) : EngineDriver::Protocol::Management?
      @@driver_proc_managers[path]?
    end

    def start
      # Self-register
      spawn discovery.register { balance_modules }

      # Listen for incoming module changes
      spawn watch_modules

      balance_modules
    end

    def start_module(mod : Model::Module)
      cs = mod.control_system.as(Model::ControlSystem)

      # Start format
      payload = {
        ip:             mod.ip,
        port:           mod.port,
        udp:            mod.udp,
        tls:            mod.tls,
        makebreak:      mod.makebreak,
        role:           mod.role,
        settings:       mod.merge_settings,
        control_system: {
          id:       mod.control_system.id,
          name:     cs.name,
          email:    cs.email,
          capacity: cs.capacity,
          features: cs.features,
          bookable: cs.bookabele,
        },
      }.to_json

      mod_id = mod.id.as(String)
      proc_manager = manager_by_module_id[mod_id]

      logger.info("starting module protocol manager: module_id=#{mod_id} driver_path=#{proc_manager.driver_path}")
      proc_manager.start(mod_id, payload)
    end

    def stop_module(mod : Model::Module)
      mod_id = mod.id.as(String)
      manager_by_module_id(mod_id).not_nil!.stop(mod_id)
    end

    # Stop and remove the module from node
    def remove_module(mod : Model::Module)
      manager_by_module_id(mod_id).stop(mod_id)
      @@module_proc_managers.delete(mod_id)
    end

    def balance_modules
      Model::Module.all.each &->load_module(Model::Module)
    end

    # Load the module if current node is responsible
    def load_module(mod : Model::Module)
      mod_id = mod.id.as(String)
      if discovery.own_node?(mod_id)
        driver = mod.driver.as(Model::Driver)
        driver_name = driver.name.as(String)
        driver_commit = driver.commit.as(String)

        # Check if the module is on the current node
        driver_path = driver_path(driver_name, driver_commit)
        unless File.exists?(driver_path)
          logger.error("driver does not exist: driver_name=#{driver_name} driver_commit=#{driver_commit} module_id=#{mod_id}")
          return
        end

        if @@module_proc_managers[mod_id]?
          # Module already loaded
          logger.info("module already loaded: module_id=#{mod_id} driver_name=#{driver_name} driver_commit=#{driver_commit}")
        elsif (existing_driver_manager = @@driver_proc_managers[driver_path]?)
          # Use the existing driver protocol manager
          @@module_proc_managers[mod_id] = existing_driver_manager
        else
          # Create a new protocol manager
          proc_manager = EngineDriver::Protocol::Manangement.new(driver_path, logger)
          @@driver_proc_managers[driver_path] = proc_manager
          @@module_proc_managers[mod_id] = proc_manager
        end

        start_module(mod)
      elsif (protocol_manager == @@module_proc_managers[mod_id]?)
        # Not on node, but protocol manager exists
        logger.info("stopping module protocol manager: module_id=#{mod_id}")
        remove_module(mod)
      end
    end
  end
end
