require "models/module"
require "models/control_system"
require "models/settings"
require "models/driver"

require "action-controller"
require "clustering"
require "driver/protocol/management"
require "drivers/compiler"
require "drivers/helper"
require "habitat"
require "hound-dog"
require "rethinkdb-orm/utils/changefeed"

module PlaceOS
  class Core::ModuleManager
    include Drivers::Helper

    alias TaggedLogger = ActionController::Logger::TaggedLogger

    # In k8s we can grab the Pod information from the environment
    # https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/#use-pod-fields-as-values-for-environment-variables
    CORE_HOST = ENV["CORE_HOST"]? || System.hostname
    CORE_PORT = (ENV["CORE_PORT"]? || "3000").to_i

    class_property uri : URI = URI.new("http", CORE_HOST, CORE_PORT)
    class_property logger : TaggedLogger = TaggedLogger.new(ActionController::Base.settings.logger)

    getter clustering : Clustering
    getter discovery : HoundDog::Discovery

    delegate stop, to: clustering

    # From environment
    @@instance : ModuleManager?

    getter? started = false

    # Class to be used as a singleton
    def self.instance : ModuleManager
      (@@instance ||= ModuleManager.new(uri: self.uri, logger: self.logger)).as(ModuleManager)
    end

    # Mapping from module_id to protocol manager
    @module_proc_managers = {} of String => Driver::Protocol::Management
    # Mapping from driver path to protocol manager
    @driver_proc_managers = {} of String => Driver::Protocol::Management

    # Start up process is as follows..
    # - registered
    # - consist hash all modules to determine loadable modules
    # - lazily start the driver processes
    # - launch the modules on those processes etc
    # - once load complete, mark in etcd that load is complete
    def initialize(
      uri : String | URI,
      logger : TaggedLogger? = nil,
      discovery : HoundDog::Discovery? = nil,
      clustering : Clustering? = nil
    )
      @uri = uri.is_a?(URI) ? uri : URI.parse(uri)
      ModuleManager.uri = @uri

      @logger = logger if logger
      @discovery = discovery || HoundDog::Discovery.new(service: "core", uri: @uri)
      @clustering = clustering || Clustering.new(
        uri: @uri,
        discovery: @discovery,
        logger: @logger
      )
    end

    def watch_modules
      Model::Module.changes.each do |change|
        mod = change[:value]
        mod_id = mod.id.as(String)
        if change[:event] == RethinkORM::Changefeed::Event::Deleted
          remove_module(mod) if manager_by_module_id(mod_id)
        else
          if mod.running_changed?
            # Running state of the module changed
            mod.running ? start_module(mod) : stop_module(mod)
          else
            # Load/Reload the module
            load_module(mod)
          end
        end
      end
    end

    # The number of drivers loaded on current node
    def running_drivers
      @driver_proc_managers.size
    end

    # The number of module processes on current node
    def running_modules
      @module_proc_managers.size
    end

    def manager_by_module_id(mod_id : String) : Driver::Protocol::Management?
      @module_proc_managers[mod_id]?
    end

    def manager_by_driver_path(path : String) : Driver::Protocol::Management?
      @driver_proc_managers[path]?
    end

    # Map reduce the querying of what modules are loaded on running drivers
    def loaded_modules : Hash(String, Array(String))
      Promise.all(@driver_proc_managers.map { |driver, manager|
        Promise.defer { {driver, manager.info} }
      }).then { |driver_info|
        loaded = {} of String => Array(String)
        driver_info.each { |(driver, info)| loaded[driver] = info }
        loaded
      }.get
    end

    def start
      # Start clustering process
      clustering.start { |nodes| stabilize(nodes) }
      # Listen for incoming module changes
      spawn(same_thread: true) { watch_modules }

      logger.tag_info("loaded modules", drivers: running_drivers, modules: running_modules)
      Fiber.yield

      @started = true

      self
    end

    def start_module(mod : Model::Module)
      # Start format
      payload = mod.to_json.rchop

      # The settings object needs to be unescaped
      payload = %(#{payload},"control_system":#{mod.control_system.to_json},"settings":#{mod.merge_settings}})

      mod_id = mod.id.as(String)
      proc_manager = manager_by_module_id(mod_id)

      raise ModuleError.new("No protocol manager for #{mod_id}") unless proc_manager

      logger.tag_info("starting module protocol manager", module_id: mod_id, driver: mod.driver.try &.name)
      proc_manager.start(mod_id, payload)
    end

    # Stop module on node
    def stop_module(mod : Model::Module)
      mod_id = mod.id.as(String)
      manager_by_module_id(mod_id).try &.stop(mod_id)
    end

    # Stop and remove the module from node
    def remove_module(mod : Model::Module)
      remove_module(mod.id.as(String))
    end

    # :ditto:
    def remove_module(module_id : String)
      manager_by_module_id(module_id).try &.stop(module_id)

      driver_path = path_for?(module_id)
      existing_manager = @module_proc_managers.delete(module_id)

      no_module_references = @module_proc_managers.select do |_, manager|
        manager == existing_manager
      end.empty?

      # Delete driver indexed manager if there are no other module references.
      if driver_path && no_module_references
        @driver_proc_managers.delete(driver_path)
      end
    end

    # HACK: get the driver path from the module_id
    def path_for?(module_id)
      @module_proc_managers[module_id]?.try do |manager|
        @driver_proc_managers.key_for?(manager)
      end
    end

    def stabilize(nodes : Array(HoundDog::Service::Node))
      # create a one off rendezvous hash with nodes from the stabilization event
      rendezvous_hash = RendezvousHash.new(nodes: nodes.map(&->HoundDog::Discovery.to_hash_value(HoundDog::Service::Node)))
      Model::Module.all.each do |m|
        load_module(m, rendezvous_hash)
      end
    end

    # Used in `on_exec` for locating the remote module
    def which_core(hash_id : String) : URI
      node = discovery.find?(hash_id)
      raise "no registered core instances" unless node
      node[:uri]
    end

    def on_exec(request : Request, response_cb : Proc(Request, Nil))
      # Protocol.instance.expect_response(@module_id, @reply_id, "exec", request, raw: true)
      remote_module_id = request.id
      raw_execute_json = request.payload.not_nil!

      core_uri = which_core(remote_module_id)

      # If module maps to this node
      if core_uri == uri
        if manager = @module_proc_managers[remote_module_id]?
          # responds with a JSON string
          request.payload = manager.execute(remote_module_id, raw_execute_json)
        else
          raise "could not locate module #{remote_module_id}. It may not be running."
        end
      else
        # build request
        core_uri.path = "/api/core/v1/command/#{remote_module_id}/execute"
        response = HTTP::Client.post(
          core_uri,
          headers: HTTP::Headers{"X-Request-ID" => "int-#{request.reply}-#{remote_module_id}-#{Time.utc.to_unix_ms}"},
          body: raw_execute_json
        )

        case response.status_code
        when 200
          # exec was successful, json string returned
          request.payload = response.body
        when 203
          # exec sent to module and it raised an error
          info = NamedTuple(message: String, backtrace: Array(String)?).from_json(response.body)
          request.payload = info[:message]
          request.backtrace = info[:backtrace]
          request.error = "RequestFailed"
        else
          # some other failure 3
          request.payload = "unexpected response code #{response.status_code}"
          request.error = "UnexpectedFailure"
        end
      end

      response_cb.call(request)
    rescue error
      request.set_error(error)
      response_cb.call(request)
    end

    def save_setting(module_id : String, setting_name : String, setting_value : YAML::Any)
      mod = PlaceOS::Model::Module.find(module_id).not_nil!
      if setting = mod.settings_at?(:none)
      else
        setting = PlaceOS::Model::Settings.new
        setting.parent = mod
        setting.encryption_level = :none
      end

      settings_hash = setting.any
      settings_hash[YAML::Any.new(setting_name)] = setting_value
      setting.settings_string = settings_hash.to_yaml
      setting.save!
    end

    alias Request = PlaceOS::Driver::Protocol::Request

    # Load the module if current node is responsible
    def load_module(mod : Model::Module, rendezvous_hash : RendezvousHash = discovery.rendezvous)
      mod_id = mod.id.as(String)

      module_uri = rendezvous_hash[mod_id]?.try do |hash_value|
        HoundDog::Discovery.from_hash_value(hash_value)[:uri]
      end

      if module_uri == uri
        driver = mod.driver.as(Model::Driver)
        driver_name = driver.name.as(String)
        driver_file_name = driver.file_name.as(String)
        driver_commit = driver.commit.as(String)

        # Check if the module is on the current node
        unless (driver_path = PlaceOS::Drivers::Compiler.is_built?(driver_file_name, driver_commit))
          logger.tag_error("driver does not exist", driver_name: driver_name, driver_commit: driver_commit, module_id: mod_id)
          return
        end

        if manager_by_module_id(mod_id)
          # Module already loaded
          logger.tag_info("module already loaded", module_id: mod_id, driver_name: driver_name, driver_commit: driver_commit)
        elsif (existing_driver_manager = manager_by_driver_path(driver_path))
          # Use the existing driver protocol manager
          @module_proc_managers[mod_id] = existing_driver_manager
        else
          # Create a new protocol manager
          proc_manager = Driver::Protocol::Management.new(driver_path, logger)

          # Hook up the callbacks
          proc_manager.on_exec = ->(request : Request, response_cb : Proc(Request, Nil)) {
            on_exec(request, response_cb); nil
          }
          proc_manager.on_setting = ->(module_id : String, setting_name : String, setting_value : YAML::Any) {
            save_setting(module_id, setting_name, setting_value); nil
          }

          @driver_proc_managers[driver_path] = proc_manager
          @module_proc_managers[mod_id] = proc_manager
        end

        start_module(mod)
      elsif manager_by_module_id(mod_id)
        # Not on node, but protocol manager exists
        logger.tag_info("stopping module protocol manager", module_id: mod_id)
        remove_module(mod)
      end
    end

    protected getter uri : URI = ModuleManager.uri
    protected getter logger : TaggedLogger = ModuleManager.logger
  end
end
