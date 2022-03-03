require "clustering"
require "hound-dog"
require "mutex"
require "redis"
require "uri/json"

require "placeos-compiler/compiler"
require "placeos-compiler/helper"
require "placeos-models/control_system"
require "placeos-models/driver"
require "placeos-models/module"
require "placeos-models/settings"
require "placeos-resource"

require "../placeos-edge/server"

require "../constants"
require "./process_manager/edge"
require "./process_manager/local"

module PlaceOS::Core
  class ModuleManager < Resource(Model::Module)
    include Compiler::Helper

    class_property uri : URI = URI.new("http", CORE_HOST, CORE_PORT)

    getter clustering : Clustering
    getter discovery : HoundDog::Discovery

    delegate stop, to: clustering

    # TODO: Remove after this is resolved https://github.com/place-technology/roadmap/issues/24
    delegate path_for?, to: local_processes

    delegate manage_edge, to: edge_processes

    delegate own_node?, to: discovery

    getter? started = false

    # Redis channel that cluster leader publishes stable cluster versions to
    REDIS_VERSION_CHANNEL = "cluster/cluster_version"

    getter redis : Redis { Redis.new(url: REDIS_URL) }

    # Singleton configured from environment
    class_getter instance : ModuleManager { ModuleManager.new(uri: self.uri) }

    # Manager for remote edge module processes
    getter edge_processes : Edge::Server = Edge::Server.new

    # Manager for local module processes
    getter local_processes : ProcessManager::Local { ProcessManager::Local.new(discovery) }

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
      super()
    end

    def start
      # Start clustering process
      clustering.start(on_stable: ->publish_version(String)) do |nodes|
        stabilize(nodes)
      end

      super

      @started = true
      self
    end

    def process_resource(action : Resource::Action, resource mod : Model::Module) : Resource::Result
      case action
      in .created?
        load_module(mod)
        Resource::Result::Success
      in .deleted?
        unload_module(mod)
        Resource::Result::Success
      in .updated?
        return Resource::Result::Skipped unless own_node?(mod.id.as(String))

        if ModuleManager.needs_restart?(mod)
          # Changes to Module state which requires a restart
          mod.running ? restart_module(mod) : stop_module(mod)
          Resource::Result::Success
        elsif mod.running_changed?
          # Running state of the module has changed
          mod.running ? start_module(mod) : stop_module(mod)
          Resource::Result::Success
        else
          Resource::Result::Skipped
        end
      end
    end

    # Module lifecycle
    ###############################################################################################

    # Load the module if current node is responsible
    #
    def load_module(mod : Model::Module, rendezvous_hash : RendezvousHash = discovery.rendezvous)
      module_id = mod.id.as(String)

      if ModuleManager.core_uri(mod, rendezvous_hash) == uri
        driver = mod.driver!
        driver_id = driver.id.as(String)
        repository_folder = driver.repository.not_nil!.folder_name

        ::Log.with_context(
          driver_id: driver_id,
          module_id: module_id,
          module_name: mod.name,
          custom_name: mod.custom_name,
          driver_name: driver.name,
          driver_commit: driver.commit,
        ) do
          driver_path = PlaceOS::Compiler.is_built?(driver.file_name, repository_folder, driver.commit, id: driver_id)
          # Check if the driver is built
          if driver_path.nil?
            Log.error { "driver does not exist for module" }
            return
          end

          process_manager(mod, &.load(module_id, driver_path))
        end

        start_module(mod) if mod.running
      elsif process_manager(mod, &.module_loaded?(module_id))
        # Not on node, but protocol manager exists
        Log.info { {message: "unloading module no longer on node", module_id: module_id} }
        unload_module(mod)
      end
    end

    # Stop and unload the module from node
    #
    def unload_module(mod : Model::Module)
      stop_module(mod)

      module_id = mod.id.as(String)
      process_manager(mod, &.unload(module_id))
      Log.info { {message: "unloaded module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
    end

    def start_module(mod : Model::Module)
      module_id = mod.id.as(String)

      process_manager(mod) { |manager| manager.start(module_id, ModuleManager.start_payload(mod)) }

      Log.info { {message: "started module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
    end

    def restart_module(mod : Model::Module)
      module_id = mod.id.as(String)

      stopped = process_manager(mod, &.stop(module_id))

      if stopped
        start_module(mod)
        Log.info { {message: "restarted module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
      else
        Log.info { {message: "failed to restart module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
      end
    end

    # Stop module on node
    #
    def stop_module(mod : Model::Module)
      module_id = mod.id.as(String)

      process_manager(mod, &.stop(module_id))
      Log.info { {message: "stopped module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
    end

    # Update/start modules with new configuration
    #
    def refresh_module(mod : Model::Module)
      process_manager(mod) do |_manager|
        mod.running.tap { |running| start_module(mod) if running }
      end
    end

    # Stops modules on stale driver and starts them on the new driver
    #
    # Returns the stale driver path
    def reload_modules(driver : Model::Driver) : Path?
      driver_id = driver.id.as(String)
      # Set when a module_manager found for stale driver
      stale_path = driver.modules.reduce(nil) do |path, mod|
        module_id = mod.id.as(String)

        # Grab the stale driver path, if there is one
        path = path_for?(module_id) if path.nil?

        # Save a lookup
        mod.driver = driver

        callbacks = process_manager(mod) do |manager|
          # Remove debug callbacks
          manager.ignore(module_id).tap do
            # Unload the module running on the stale driver
            manager.stop(module_id)
            unload_module(mod)
          end
        end

        if started?
          # Reload module on new driver binary
          Log.debug { {
            message:   "loading module after compilation",
            module_id: module_id,
            driver_id: driver_id,
            file_name: driver.file_name,
            commit:    driver.commit,
          } }
          load_module(mod)
          process_manager(mod) do |manager|
            # Move callbacks to new module instance
            callbacks.try &.each do |callback|
              manager.debug(module_id, &callback)
            end
          end
        end
        path
      end

      stale_path || driver.commit_was.try { |commit|
        # Try to create a driver path from what the commit used to be
        Path[Compiler::Helper.driver_binary_path(driver.file_name, commit, driver_id)]
      }
    end

    ###############################################################################################

    # Delegate `Model::Module` to a `ProcessManager`, either local or on an edge
    #
    def process_manager(mod : Model::Module | String, & : ProcessManager ->)
      edge_id = case mod
                in Model::Module
                  mod.edge_id if mod.on_edge?
                in String
                  # TODO: Cache module to edge relation
                  Model::Module.find!(mod).edge_id if Model::Module.has_edge_hint?(mod)
                end

      if edge_id
        if (manager = edge_processes.for?(edge_id)).nil?
          Log.error { "missing edge manager for #{edge_id}" }
          return
        end
        yield manager
      else
        yield local_processes
      end
    end

    def process_manager(driver_key : String, edge_id : String?) : ProcessManager?
      manager = if edge_id.nil? || !own_node?(edge_id)
                  local_processes
                else
                  edge_processes.for?(edge_id)
                end

      manager if manager && manager.driver_loaded?(driver_key)
    end

    # Clustering
    ###############################################################################################

    private getter queued_stabilization_events = Atomic(Int32).new(0)
    private getter stabilize_lock = Mutex.new

    # OPTIMIZE: Experiment with batch size
    private STABILIZE_BATCH_SIZE = 32

    # Run through modules and load to a stable state.
    #
    # Uses a semaphore to ensure intermediary cluster events don't trigger stabilization.
    def stabilize(nodes : Array(HoundDog::Service::Node)) : Bool
      queued_stabilization_events.add(1)
      stabilize_lock.synchronize do
        queued_stabilization_events.add(-1)
        return false unless queued_stabilization_events.get.zero?

        Log.debug { {message: "stabilizing", nodes: nodes.to_json} }

        # Create a one off rendezvous hash with nodes from the stabilization event
        rendezvous_hash = RendezvousHash.new(nodes: nodes.map(&->HoundDog::Discovery.to_hash_value(HoundDog::Service::Node)))

        success_count, fail_count = 0_i64, 0_i64
        waiting = Array(Promise::DeferredPromise(Nil)).new(STABILIZE_BATCH_SIZE)
        Model::Module.all.in_groups_of(STABILIZE_BATCH_SIZE, reuse: true) do |modules|
          modules.each.reject(Nil).each do |mod|
            waiting << Promise.defer(same_thread: true) do
              begin
                load_module(mod, rendezvous_hash)
                success_count += 1
              rescue e
                Log.error(exception: e) { {message: "failed to load module during stabilization", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
                fail_count += 1
              end
              nil
            end
            Promise.all(waiting).get
            waiting.clear
          end
        end

        Log.info { {message: "finished loading modules stabilization", success: success_count, failure: fail_count} }
        true
      end
    end

    # Determine if a module is an edge module and allocated to the current core node.
    #
    def on_managed_edge?(mod : Model::Module)
      mod.on_edge? && own_node?(mod.edge_id.as(String))
    end

    # Publish cluster version to redis
    #
    def publish_version(cluster_version : String)
      redis.publish(REDIS_VERSION_CHANNEL, cluster_version)

      nil
    end

    # Route via `edge_id` if the Module is on an Edge, otherwise the Module's id
    #
    def self.hash_id(mod : String | Model::Module)
      case mod
      in String
        if Model::Module.has_edge_hint?(mod)
          Model::Module.find!(mod).edge_id.as(String)
        else
          mod
        end
      in Model::Module
        mod.on_edge? ? mod.edge_id.as(String) : mod.id.as(String)
      end
    end

    def self.core_uri(mod : Model::Module | String, rendezvous_hash : RendezvousHash)
      rendezvous_hash[hash_id(mod)]?.try do |hash_value|
        HoundDog::Discovery.from_hash_value(hash_value)[:uri]
      end
    end

    protected getter uri : URI = ModuleManager.uri

    # Helpers
    ###########################################################################

    def self.start_payload(mod : Model::Module)
      begin
        # Merge module settings
        merged_settings = mod.merge_settings
      rescue e
        raise ModuleError.new("Failed to merge module settings #{e.message}")
      end

      # Start format
      payload = mod.to_json.rchop

      # The settings object needs to be unescaped
      %(#{payload},"control_system":#{mod.control_system.to_json},"settings":#{merged_settings}})
    end

    def self.execute_payload(method : String | Symbol, args : Enumerable? = nil, named_args : Hash | NamedTuple | Nil = nil)
      {
        "__exec__" => method,
        method     => args || named_args,
      }.to_json
    end

    def self.needs_restart?(mod : Model::Module) : Bool
      mod.ip_changed? || mod.port_changed? || mod.tls_changed? || mod.udp_changed? || mod.makebreak_changed? || mod.uri_changed?
    end
  end
end
