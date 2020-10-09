require "clustering"
require "hound-dog"
require "mutex"
require "redis"

require "placeos-compiler/compiler"
require "placeos-compiler/helper"
require "placeos-models/control_system"
require "placeos-models/driver"
require "placeos-models/module"
require "placeos-models/settings"
require "placeos-resource"

require "../constants"
require "./processes/edge"
require "./processes/local"

module PlaceOS::Core
  class ModuleManager < Resource(Model::Module)
    include Compiler::Helper

    class_property uri : URI = URI.new("http", CORE_HOST, CORE_PORT)

    getter clustering : Clustering
    getter discovery : HoundDog::Discovery

    delegate stop, to: clustering

    # Todo: remove
    delegate path_for?, to: local_processes

    getter? started = false

    # Redis channel that cluster leader publishes stable cluster versions to
    REDIS_VERSION_CHANNEL = "cluster/cluster_version"

    getter redis : Redis { Redis.new(url: REDIS_URL) }

    # Singleton configured from environment
    class_getter instance : ModuleManager { ModuleManager.new(uri: self.uri) }

    # Manager for remote edge module processes
    getter edge_processes : Processes::Edge { Processes::Edge.new }

    # Manager for local module processes
    getter local_processes : Processes::Local { Processes::Local.new }

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

    def process_resource(action : Resource::Action, resource : Model::Module) : Resource::Result
      mod = resource
      case action
      in .created?
        load_module(mod)
        Resource::Result::Success
      in .deleted?
        unload_module(mod)
        Resource::Result::Success
      in .updated?
        return Resource::Result::Skipped unless discovery.own_node?(mod.id.as(String))

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

    def on_managed_edge?(mod : Model::Module)
      mod.on_edge? && discovery.own_node?(mod.edge_id.as(String))
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

    def start_module(mod : Model::Module)
      begin
        # Merge module settings
        merged_settings = mod.merge_settings
      rescue e
        raise ModuleError.new("Failed to merge module settings")
      end

      # Start format
      payload = mod.to_json.rchop

      # The settings object needs to be unescaped
      payload = %(#{payload},"control_system":#{mod.control_system.to_json},"settings":#{merged_settings}})

      module_id = mod.id.as(String)

      process_manager(mod) { |manager| manager.start(module_id, payload) }

      Log.info { {message: "started module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
    end

    def process_manager(mod : Model::Module | String, & : ProcessManager ->)
      edge = case mod
             in Model::Module then mod.on_edge?
             in String        then Model::Module.has_edge_hint?(mod)
             end

      if edge
        yield edge_processes
      else
        yield local_processes
      end
    end

    def restart_module(mod : Model::Module)
      module_id = mod.id.as(String)

      stopped = process_manager(mod) { |manager| manager.stop(module_id) }

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

    # Stop and unload the module from node
    #
    def unload_module(mod : Model::Module)
      stop_module(mod)

      module_id = mod.id.as(String)
      process_manager(mod, &.unload(module_id))
      Log.info { {message: "unloaded module", module_id: mod.id, name: mod.name, custom_name: mod.custom_name} }
    end

    def stabilize(nodes : Array(HoundDog::Service::Node))
      # create a one off rendezvous hash with nodes from the stabilization event
      rendezvous_hash = RendezvousHash.new(nodes: nodes.map(&->HoundDog::Discovery.to_hash_value(HoundDog::Service::Node)))
      Model::Module.all.each do |m|
        begin
          load_module(m, rendezvous_hash)
        rescue e
          Log.error(exception: e) { {message: "failed to load module during stabilization", module_id: m.id, name: m.name, custom_name: m.custom_name} }
        end
      end
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

    # Used in `on_exec` for locating the remote module
    #
    def which_core(module_id : String) : URI
      node = discovery.find?(hash_id(module_id))
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

    alias Request = PlaceOS::Driver::Protocol::Request

    def self.core_uri(mod : Model::Module | String, rendezvous_hash : RendezvousHash)
      rendezvous_hash[hash_id(mod)]?.try do |hash_value|
        HoundDog::Discovery.from_hash_value(hash_value)[:uri]
      end
    end

    # Load the module if current node is responsible
    #
    def load_module(mod : Model::Module, rendezvous_hash : RendezvousHash = discovery.rendezvous)
      module_id = mod.id.as(String)

      if ModuleManager.core_uri(mod, rendezvous_hash) == uri
        driver = mod.driver!
        driver_id = driver.id.as(String)

        ::Log.with_context do
          Log.context.set({
            module_id:     module_id,
            module_name:   mod.name,
            custom_name:   mod.custom_name,
            driver_name:   driver.name,
            driver_commit: driver.commit,
          })

          # Check if the driver is built
          unless (driver_path = PlaceOS::Compiler.is_built?(driver.file_name, driver.commit, id: driver_id))
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

    # Update/start modules with new configuration
    #
    def refresh_module(mod : Model::Module)
      process_manager(mod) do |_manager|
        if mod.running
          start_module(mod)
          true
        else
          false
        end
      end
    end

    protected getter uri : URI = ModuleManager.uri

    # Helpers
    ###########################################################################

    def self.needs_restart?(mod : Model::Module) : Bool
      mod.ip_changed? || mod.port_changed? || mod.tls_changed? || mod.udp_changed? || mod.makebreak_changed? || mod.uri_changed?
    end
  end
end
