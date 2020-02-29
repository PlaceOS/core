require "engine-models/module"
require "engine-models/control_system"
require "engine-models/settings"
require "engine-models/driver"

require "action-controller"
require "clustering"
require "engine-driver/protocol/management"
require "engine-drivers/compiler"
require "engine-drivers/helper"
require "habitat"
require "hound-dog"
require "rethinkdb-orm/utils/changefeed"

module ACAEngine
  class Core::ModuleManager
    include Drivers::Helper

    alias TaggedLogger = ActionController::Logger::TaggedLogger

    # In k8s we can grab the Pod information from the environment
    # https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/#use-pod-fields-as-values-for-environment-variables
    CORE_HOST = ENV["CORE_HOST"]? || "localhost"
    CORE_PORT = (ENV["CORE_PORT"]? || "3000").to_i

    class_property uri : URI = URI.new("http", CORE_HOST, CORE_PORT)
    class_property logger : TaggedLogger = TaggedLogger.new(ActionController::Base.settings.logger)

    getter clustering : Clustering
    getter discovery : HoundDog::Discovery

    delegate stop, to: clustering

    # From environment
    @@instance : ModuleManager?

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

    def start
      # Start clustering process
      clustering.start { |nodes| stabilize(nodes) }
      # Listen for incoming module changes
      spawn(same_thread: true) { watch_modules }

      logger.tag_info("loaded modules", drivers: running_drivers, modules: running_modules)
      Fiber.yield
      self
    end

    def start_module(mod : Model::Module)
      cs = mod.control_system.as(Model::ControlSystem)

      # Start format
      payload = {
        ip:   mod.ip,
        port: mod.port,
        # TODO: remove '|| false' after Module has updated defaults
        udp:            mod.udp || false,
        tls:            mod.tls || false,
        makebreak:      mod.makebreak,
        role:           mod.role,
        settings:       mod.merge_settings,
        control_system: {
          id:   cs.id,
          name: cs.name,
          # TODO: remove '|| ""' after ControlSystem has updated defaults
          email:    cs.email || "",
          features: cs.features || "",
          capacity: cs.capacity,
          bookable: cs.bookable,
        },
      }.to_json

      # NOTE: The settings object needs to be unescaped
      # OPTIMIZE: Might be better if the driver parses the setttings as a seperate JSON chunk
      payload = payload.gsub(/"settings":"{(.*)}",/) do |m1|
        m1.gsub(/"{(.*)}"/) do |m2|
          m2.strip('"')
        end
      end

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
      mod_id = mod.id.as(String)
      manager_by_module_id(mod_id).try &.stop(mod_id)
      @module_proc_managers.delete(mod_id)
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
      mod = ACAEngine::Model::Module.find(module_id).not_nil!
      if setting = mod.settings_at?(:none)
      else
        setting = ACAEngine::Model::Settings.new
        setting.parent = mod
        setting.encryption_level = :none
      end

      settings_hash = setting.any
      settings_hash[YAML::Any.new(setting_name)] = setting_value
      setting.settings_string = settings_hash.to_yaml
      setting.save!
    end

    alias Request = ACAEngine::Driver::Protocol::Request

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
        unless (driver_path = ACAEngine::Drivers::Compiler.is_built?(driver_file_name, driver_commit))
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
