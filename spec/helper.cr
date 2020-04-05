require "spec"
require "uuid"
require "../lib/action-controller/spec/curl_context"

# Application config
require "../src/config"
require "../src/core"
require "../src/core/*"

require "models/spec/generator"

SPEC_DRIVER = "drivers/place/private_helper.cr"

CORE_URL = ENV["CORE_URL"]? || "http://core:3000"

# To reduce the run-time of the very setup heavy specs.
# - Use teardown if you need to clear a temporary repository
# - Use setup(fresh: true) if you require a clean working directory
TEMP_DIR = get_temp

# Set the working directory before specs
set_temporary_working_directory

LOGGER = ActionController::Logger::TaggedLogger.new(ActionController::Base.settings.logger)
LOGGER.level = Logger::Severity::DEBUG

def get_temp
  "#{Dir.tempdir}/core-spec-#{UUID.random.to_s.split('-').first}"
end

def teardown(temp_dir = TEMP_DIR)
  `rm -rf #{temp_dir}`
end

def clear_tables
  PlaceOS::Model::ControlSystem.clear
  PlaceOS::Model::Repository.clear
  PlaceOS::Model::Driver.clear
  PlaceOS::Model::Module.clear
end

# Remove the shared test directory
Spec.after_suite &->teardown

macro around_suite(block)
  Spec.before_suite do
    {{ block }}.call
  end
  Spec.after_suite do
    {{ block }}.call
  end
end

Spec.before_suite &->teardown

around_suite ->{
  clear_tables
  HoundDog::Service.clear_namespace
}

Spec.after_suite do
  PlaceOS::Core::ResourceManager.instance.stop
  `pkill -f "core-spec"`
end

# Set up a temporary directory
def set_temporary_working_directory(fresh : Bool = false) : String
  temp_dir = fresh ? get_temp : TEMP_DIR
  PlaceOS::Drivers::Compiler.bin_dir = "#{temp_dir}/bin"
  PlaceOS::Drivers::Compiler.drivers_dir = "#{temp_dir}/repositories/private-drivers"
  PlaceOS::Drivers::Compiler.repository_dir = "#{temp_dir}/repositories"

  parallel(
    Dir.mkdir_p(PlaceOS::Drivers::Compiler.bin_dir),
    Dir.mkdir_p(PlaceOS::Drivers::Compiler.drivers_dir),
    Dir.mkdir_p(PlaceOS::Drivers::Compiler.repository_dir),
  )

  temp_dir
end

# Create models for a test
def setup(fresh : Bool = false)
  # Set up a temporary directory
  temp_dir = set_temporary_working_directory(fresh)

  # Repository metadata
  repository_uri = "https://github.com/placeos/private-drivers"
  repository_name = "Private Drivers"
  repository_folder_name = "private-drivers"

  # Driver metadata
  driver_file_name = "drivers/place/private_helper.cr"
  driver_module_name = "PrivateHelper"
  driver_name = "spec_helper"
  driver_commit = "4be0571"
  driver_role = PlaceOS::Model::Driver::Role::Logic

  existing_repo = PlaceOS::Model::Repository.where(uri: repository_uri).first?
  existing_driver = existing_repo.try(&.drivers.first?)
  existing_module = existing_driver.try(&.modules.first?)

  if existing_repo && existing_driver && existing_module
    repository, driver, mod = existing_repo, existing_driver, existing_module
  else
    # Clear tables
    PlaceOS::Model::ControlSystem.clear
    PlaceOS::Model::Driver.clear
    PlaceOS::Model::Module.clear
    PlaceOS::Model::Repository.clear

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

    driver.repository = repository
    driver.save!

    mod = PlaceOS::Model::Generator.module(driver: driver)
    mod.running = true
    mod.save!

    control_system = mod.control_system.as(PlaceOS::Model::ControlSystem)
    control_system.modules = [mod.id.as(String)]
    control_system.save!
  end

  {temp_dir, repository, driver, mod}
end

def create_resources(fresh : Bool = false, process : Bool = true)
  # Prepare models, set working dir
  _, repository, driver, mod = setup(fresh)

  # Clone, compile
  if process
    PlaceOS::Core::ResourceManager.instance(testing: true).start { }
  end

  {repository, driver, mod}
end

class DiscoveryMock < HoundDog::Discovery
  def own_node?(key : String) : Bool
    true
  end

  def etcd_nodes
    [@service_events.node].map &->HoundDog::Discovery.to_hash_value(HoundDog::Service::Node)
  end
end

class MockClustering < Clustering
  def start(&stabilize : Array(HoundDog::Service::Node) ->)
    @stabilize = stabilize
    stabilize.call([discovery.node])
  end

  def stop
  end
end
