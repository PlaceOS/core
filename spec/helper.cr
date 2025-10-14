require "uuid"
require "git-repository"

# Helper methods for testing controllers
require "action-controller/spec_helper"

# Application config
require "../src/config"
require "../src/placeos-core"
require "../src/placeos-core/*"

require "placeos-models/spec/generator"

require "spec"

SPEC_DRIVER = "drivers/place/private_helper.cr"
CORE_URL    = ENV["CORE_URL"]? || "http://core:3000"

# To reduce the run-time of the very setup heavy specs.
# - Use teardown if you need to clear a temporary repository
# - Use setup(fresh: true) if you require a clean working directory

PRIVATE_DRIVER_ID = "driver-#{random_id}"

def random_id
  UUID.random.to_s.split('-').first
end

def clear_tables
  PlaceOS::Model::ControlSystem.clear
  PlaceOS::Model::Repository.clear
  PlaceOS::Model::Driver.clear
  PlaceOS::Model::Module.clear
  PlaceOS::Model::Edge.clear
end

def clustering_mock
  MockClustering.new("core")
end

def discovery_mock
  Clustering::Discovery.new(clustering_mock)
end

def module_manager_mock
  PlaceOS::Core::ModuleManager.new(CORE_URL, clustering: clustering_mock)
end

macro around_suite(block)
  Spec.before_suite do
    {{ block }}.call
  end
  Spec.after_suite do
    {{ block }}.call
  end
end

around_suite -> {
  clear_tables
}

PgORM::Database.configure { |_| }
Spec.before_suite do
  Log.builder.bind("*", backend: PlaceOS::LogBackend.log_backend, level: :warn)
  Log.builder.bind("place_os.*", backend: PlaceOS::LogBackend.log_backend, level: :error)
  Log.builder.bind("http.client", backend: PlaceOS::LogBackend.log_backend, level: :warn)
  Log.builder.bind("clustering", backend: PlaceOS::LogBackend.log_backend, level: :error)
  Log.builder.bind("hound_dog.*", backend: PlaceOS::LogBackend.log_backend, level: :error)
end

Spec.after_suite do
  PlaceOS::Core::ResourceManager.instance.stop
  Log.builder.bind("*", backend: PlaceOS::LogBackend.log_backend, level: :error)
  puts "\n> Terminating stray driver processes"
  `pkill -f ".*core-spec.*"` rescue nil
end

# Create models for a test
# ameba:disable Metrics/CyclomaticComplexity
def setup(role : PlaceOS::Model::Driver::Role? = nil, use_head : Bool = false)
  # Repository metadata
  repository_uri = "https://github.com/placeos/private-drivers"
  repository_name = "Private Drivers"
  repository_folder_name = "private-drivers"

  # Driver metadata
  driver_file_name = "drivers/place/private_helper.cr"
  driver_module_name = "PrivateHelper"
  driver_name = "spec_helper"
  driver_commit = if use_head
                    "HEAD"
                  else
                    GitRepository.new(repository_uri).commits("master", depth: 1).first.hash
                  end
  driver_role = role || PlaceOS::Model::Driver::Role::Logic

  existing_repo = PlaceOS::Model::Repository.where(uri: repository_uri).first?
  existing_driver = existing_repo.try(&.drivers.first?)
  existing_module = existing_driver.try(&.modules.first?)

  needs_control_system = driver_role.logic? && !existing_module.try(&.control_system)
  right_driver_role = role ? !!existing_driver.try(&.role.== role) : true

  if existing_repo && existing_driver && existing_module && !needs_control_system && right_driver_role
    repository, driver, mod = existing_repo, existing_driver, existing_module
  else
    clear_tables

    repository = PlaceOS::Model::Generator.repository(type: PlaceOS::Model::Repository::Type::Driver)
    repository.uri = repository_uri
    repository.name = repository_name
    repository.folder_name = repository_folder_name
    repository.save!

    driver = PlaceOS::Model::Driver.new(
      name: driver_name,
      role: driver_role,
      commit: driver_commit,
      module_name: driver_module_name,
      file_name: driver_file_name,
    )

    driver.id = PRIVATE_DRIVER_ID
    driver.repository = repository
    driver.save!

    mod = PlaceOS::Model::Generator.module(driver: driver)
    mod.running = true
    mod.save!

    control_system = if needs_control_system
                       mod.control_system = PlaceOS::Model::Generator.control_system.save! unless mod.control_system
                       mod.control_system.as(PlaceOS::Model::ControlSystem)
                     else
                       PlaceOS::Model::Generator.control_system
                     end

    control_system.modules = [mod.id.as(String)]
    control_system.save
  end

  {repository, driver, mod}
end

def create_resources(process : Bool = true, use_head : Bool = false)
  # Prepare models, set working dir
  repository, driver, mod = setup(use_head: use_head)

  resource_manager = PlaceOS::Core::ResourceManager.new(testing: true)
  resource_manager.start { } if process

  {repository, driver, mod, resource_manager}
end

# reopen this for specs
class Clustering::Discovery
  DOES_NOT_MAP = "<does-not-map>"

  def own_node?(key : String) : Bool
    key != DOES_NOT_MAP
  end
end

class MockClustering < Clustering
  NODE_ID  = "----core1----"
  NODE_URI = ENV["CORE_URL"]? || "http://core:3000"
  VERSION  = "1"

  getter uri : String = NODE_URI
  getter ulid : String = NODE_ID

  # registers this node with the cluster as a member
  def register : Bool
    rendezvous_hash = rendezvous
    @version = VERSION

    ready_cb = Proc(Nil).new do
      cluster_stable_callbacks.each do |callback|
        spawn do
          begin
            callback.call
          rescue error
            Log.error(exception: error) { "notifying cluster stable" }
          end
        end
      end
    end

    rebalance_callbacks.each do |callback|
      spawn do
        begin
          callback.call(rendezvous_hash, ready_cb)
        rescue error
          Log.error(exception: error) { "performing rebalance callback" }
        end
      end
    end
    true
  end

  # removes this node from the cluster as a member
  getter unregister : Bool = true

  # is this node registered as part of the cluster
  getter? registered : Bool = true

  # is this class watching for changes to the cluster
  # this should return true if registered returns true
  getter? watching : Bool = true

  # returns the list of known nodes
  def rendezvous : RendezvousHash
    RendezvousHash.new(nodes: [NODE_URI])
  end

  # returns a node_id => URI mapping
  def node_hash : Hash(String, URI)
    {
      NODE_ID => URI.parse(NODE_URI),
    }
  end
end
