require "placeos-models/control_system"
require "placeos-models/driver"
require "placeos-models/module"
require "placeos-models/settings"

require "clustering"
require "driver/protocol/management"
require "compiler/drivers/compiler"
require "compiler/drivers/helper"
require "habitat"
require "hound-dog"
require "mutex"
require "redis"
require "rethinkdb-orm/utils/changefeed"

module PlaceOS
  class Core::ModuleManager
    include Drivers::Helper

    # In k8s we can grab the Pod information from the environment
    # https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/#use-pod-fields-as-values-for-environment-variables
    CORE_HOST = ENV["CORE_HOST"]? || System.hostname
    CORE_PORT = (ENV["CORE_PORT"]? || "3000").to_i

    class_property uri : URI = URI.new("http", CORE_HOST, CORE_PORT)

    getter clustering : Clustering
    getter discovery : HoundDog::Discovery

    delegate stop, to: clustering

    # Redis channel that cluster leader publishes stable cluster versions to
    REDIS_VERSION_CHANNEL = "cluster/cluster_version"

    @redis : Redis?

    # Lazy getter for redis
    #
    def redis
      @redis ||= Redis.new(url: ENV["REDIS_URL"]?)
    end

    # From environment
    @@instance : ModuleManager?

    getter? started = false

    # Class to be used as a singleton
    def self.instance : ModuleManager
      (@@instance ||= ModuleManager.new(uri: self.uri)).as(ModuleManager)
    end

    # Start up process is as follows..
    # - registered
    # - consist hash all modules to determine loadable modules
    # - lazily start the driver processes
    # - launch the modules on those processes etc
    # - once load complete, mark in etcd that load is complete
    def initialize(
      uri : String | URI,
      discovery : HoundDog::Discovery? = nil,
      clustering : Clustering? = nil,
      @redis : Redis? = nil
    )
      @uri = uri.is_a?(URI) ? uri : URI.parse(uri)
      ModuleManager.uri = @uri

      @discovery = discovery || HoundDog::Discovery.new(service: "core", uri: @uri)
      @clustering = clustering || Clustering.new(
        uri: @uri,
        discovery: @discovery,
      )
    end

    def watch_modules
      Model::Module.changes.each do |change|
        mod = change[:value]
        case change[:event]
        when RethinkORM::Changefeed::Event::Created
          load_module(mod)
        when RethinkORM::Changefeed::Event::Deleted
          remove_module(mod)
        when RethinkORM::Changefeed::Event::Updated
          if ModuleManager.needs_restart?(mod)
            mod.running ? restart_module(mod) : stop_module(mod)
          elsif mod.running_changed? && discovery.own_node?(mod.id.as(String))
            # Running state of the module has changed
            mod.running ? start_module(mod) : stop_module(mod)
          end
        end
      end
    end

    # The number of drivers loaded on current node
    def running_drivers
      proc_manager_lock.synchronize do
        @driver_proc_managers.size
      end
    end

    # The number of module processes on current node
    def running_modules
      proc_manager_lock.synchronize do
        @module_proc_managers.size
      end
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
      clustering.start(on_stable: ->publish_version(String)) do |nodes|
        stabilize(nodes)
      end

      Model::Module.all.each do |mod|
        load_module(mod)
      end

      # Listen for incoming module changes
      spawn(same_thread: true) { watch_modules }

      Log.info { {message: "loaded modules", drivers: running_drivers, modules: running_modules} }
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
      proc_manager = proc_manager_by_module?(mod_id)

      raise ModuleError.new("No protocol manager for #{mod_id}") unless proc_manager

      proc_manager.start(mod_id, payload)
      Log.info { {message: "started module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
    end

    def restart_module(mod : Model::Module)
      mod_id = mod.id.as(String)
      manager = proc_manager_by_module?(mod_id)

      if manager
        manager.stop(mod_id)
        start_module(mod)
        Log.info { {message: "restarted module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
      else
        Log.error { {message: "missing protocol manager on restart", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
      end
    end

    # Stop module on node
    #
    def stop_module(mod : Model::Module)
      mod_id = mod.id.as(String)
      manager = proc_manager_by_module?(mod_id)

      if manager
        manager.stop(mod_id)
        Log.info { {message: "stopped module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
      end
    end

    # Stop and remove the module from node
    def remove_module(mod : Model::Module)
      module_id = mod.id.as(String)
      stop_module(mod)

      driver_path = path_for?(module_id)
      existing_manager = set_module_proc_manager(module_id, nil)
      Log.info { {message: "removed module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }

      no_module_references = existing_manager.nil? || proc_manager_lock.synchronize do
        @module_proc_managers.select do |_, manager|
          manager == existing_manager
        end.empty?
      end

      # Delete driver indexed manager if there are no other module references.
      if driver_path && no_module_references
        set_driver_proc_manager(driver_path, nil)
        Log.info { {message: "removed driver manager", driver: mod.driver.try(&.name), module_name: mod.name} }
      end
    end

    def stabilize(nodes : Array(HoundDog::Service::Node))
      # create a one off rendezvous hash with nodes from the stabilization event
      rendezvous_hash = RendezvousHash.new(nodes: nodes.map(&->HoundDog::Discovery.to_hash_value(HoundDog::Service::Node)))
      Model::Module.all.each do |m|
        load_module(m, rendezvous_hash)
      end
    end

    # Publish cluster version to redis
    #
    def publish_version(cluster_version : String)
      redis.publish(REDIS_VERSION_CHANNEL, cluster_version)

      nil
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
        if manager = proc_manager_by_module?(remote_module_id)
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
    #
    def load_module(mod : Model::Module, rendezvous_hash : RendezvousHash = discovery.rendezvous)
      mod_id = mod.id.as(String)
      module_uri = rendezvous_hash[mod_id]?.try do |hash_value|
        HoundDog::Discovery.from_hash_value(hash_value)[:uri]
      end

      if module_uri == uri
        driver = mod.driver.as(Model::Driver)
        driver_name = driver.name.as(String)
        driver_id = driver.id.as(String)
        driver_file_name = driver.file_name.as(String)
        driver_commit = driver.commit.as(String)

        ::Log.with_context do
          Log.context.set({
            module_id:     mod_id,
            module_name:   mod.name,
            custom_name:   mod.custom_name,
            driver_name:   driver_name,
            driver_commit: driver_commit,
          })

          # Check if the module is on the current node
          unless (driver_path = PlaceOS::Drivers::Compiler.is_built?(driver_file_name, driver_commit, id: driver_id))
            Log.error { "driver does not exist for module" }
            return
          end

          if !proc_manager_by_module?(mod_id)
            if (existing_driver_manager = proc_manager_by_driver?(driver_path))
              # Use the existing driver protocol manager
              set_module_proc_manager(mod_id, existing_driver_manager)
            else
              # Create a new protocol manager
              proc_manager = Driver::Protocol::Management.new(driver_path)

              # Hook up the callbacks
              proc_manager.on_exec = ->(request : Request, response_cb : Proc(Request, Nil)) {
                on_exec(request, response_cb); nil
              }
              proc_manager.on_setting = ->(module_id : String, setting_name : String, setting_value : YAML::Any) {
                save_setting(module_id, setting_name, setting_value); nil
              }

              set_module_proc_manager(mod_id, proc_manager)
              set_driver_proc_manager(driver_path, proc_manager)
            end

            Log.info { "loaded module" }
          else
            Log.info { "module already loaded" }
          end
        end

        start_module(mod) if mod.running
      elsif proc_manager_by_module?(mod_id)
        # Not on node, but protocol manager exists
        Log.info { {message: "removing module no longer on node", module_id: mod_id} }
        remove_module(mod)
      end
    end

    protected getter uri : URI = ModuleManager.uri

    # Helpers
    ###########################################################################

    def self.needs_restart?(mod : Model::Module) : Bool
      mod.ip_changed? || mod.port_changed? || mod.tls_changed? || mod.udp_changed? || mod.makebreak_changed? || mod.uri_changed?
    end

    # Protocol Managers
    ###########################################################################

    private getter proc_manager_lock = Mutex.new

    # Mapping from module_id to protocol manager
    @module_proc_managers = {} of String => Driver::Protocol::Management

    # Mapping from driver path to protocol manager
    @driver_proc_managers = {} of String => Driver::Protocol::Management

    protected def proc_manager_by_module?(module_id) : Driver::Protocol::Management?
      proc_manager_lock.synchronize do
        @module_proc_managers[module_id]?
      end
    end

    protected def proc_manager_by_driver?(driver_path) : Driver::Protocol::Management?
      proc_manager_lock.synchronize do
        @driver_proc_managers[driver_path]?
      end
    end

    protected def set_module_proc_manager(module_id, manager : Driver::Protocol::Management?)
      proc_manager_lock.synchronize do
        if manager.nil?
          @module_proc_managers.delete(module_id)
        else
          @module_proc_managers[module_id] = manager
          manager
        end
      end
    end

    protected def set_driver_proc_manager(driver_path, manager : Driver::Protocol::Management?)
      proc_manager_lock.synchronize do
        if manager.nil?
          @driver_proc_managers.delete(driver_path)
        else
          @driver_proc_managers[driver_path] = manager
          manager
        end
      end
    end

    # HACK: get the driver path from the module_id
    protected def path_for?(module_id)
      proc_manager_lock.synchronize do
        @module_proc_managers[module_id]?.try do |manager|
          @driver_proc_managers.key_for?(manager)
        end
      end
    end
  end
end
