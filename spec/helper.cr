require "spec"
require "../lib/action-controller/spec/curl_context"

# Application config
require "../src/config"
require "../src/engine-core"
require "../src/engine-core/*"

require "engine-models/spec/generator"

SPEC_DRIVER = "drivers/aca/private_helper.cr"

# To reduce the run-time of the very setup heavy specs.
# - Use teardown if you need to clear a temporary repository
# - Use setup(fresh: true) if you require a clean working directory
TEMP_DIR = get_temp

LOGGER = ActionController::Logger::TaggedLogger.new(ActionController::Base.settings.logger)
LOGGER.level = Logger::Severity::DEBUG

def get_temp
  "#{Dir.tempdir}/core-spec"
end

def teardown(temp_dir = TEMP_DIR)
  `rm -rf #{temp_dir}`
end

def clear_tables
  ACAEngine::Model::ControlSystem.clear
  ACAEngine::Model::Repository.clear
  ACAEngine::Model::Driver.clear
  ACAEngine::Model::Module.clear
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
  # clear_tables
  HoundDog::Service.clear_namespace
}

Spec.after_suite do
  ACAEngine::Core::ResourceManager.instance.stop
  `pkill -f "core-spec"`
end

# Set up a temporary directory
def set_temporary_working_directory(fresh : Bool = false) : String
  temp_dir = fresh ? get_temp : TEMP_DIR
  ACAEngine::Drivers::Compiler.bin_dir = "#{temp_dir}/bin"
  ACAEngine::Drivers::Compiler.drivers_dir = "#{temp_dir}/repositories/drivers"
  ACAEngine::Drivers::Compiler.repository_dir = "#{temp_dir}/repositories"

  parallel(
    Dir.mkdir_p(ACAEngine::Drivers::Compiler.bin_dir),
    Dir.mkdir_p(ACAEngine::Drivers::Compiler.drivers_dir),
    Dir.mkdir_p(ACAEngine::Drivers::Compiler.repository_dir),
  )

  temp_dir
end

# Create models for a test
def setup(fresh : Bool = false)
  # Set up a temporary directory
  temp_dir = set_temporary_working_directory(fresh)

  # Repository metadata
  repository_uri = "https://github.com/acaengine/private-drivers"
  repository_name = repository_folder_name = "drivers"

  # Driver metadata
  driver_file_name = "drivers/aca/private_helper.cr"
  driver_module_name = "PrivateHelper"
  driver_name = "spec_helper"
  driver_role = ACAEngine::Model::Driver::Role::Logic
  driver_version = SemanticVersion.new(major: 1, minor: 0, patch: 0)

  existing_repo = ACAEngine::Model::Repository.where(uri: repository_uri).first?
  existing_driver = existing_repo.try(&.drivers.first?)
  existing_module = existing_driver.try(&.modules.first?)

  if existing_repo && existing_driver && existing_module
    repository, driver, mod = existing_repo, existing_driver, existing_module
  else
    # Clear tables
    ACAEngine::Model::ControlSystem.clear
    ACAEngine::Model::Driver.clear
    ACAEngine::Model::Module.clear
    ACAEngine::Model::Repository.clear

    repository = ACAEngine::Model::Generator.repository(type: ACAEngine::Model::Repository::Type::Driver)
    repository.uri = repository_uri
    repository.name = repository_name
    repository.folder_name = repository_folder_name
    repository.save!

    driver = ACAEngine::Model::Driver.new(
      name: driver_name,
      role: driver_role,
      commit: "head",
      version: driver_version,
      module_name: driver_module_name,
      file_name: driver_file_name,
    )

    driver.repository = repository
    driver.save!

    mod = ACAEngine::Model::Generator.module(driver: driver).save!
    control_system = mod.control_system.as(ACAEngine::Model::ControlSystem)
    control_system.modules = [mod.id.as(String)]
    control_system.save!
  end

  {temp_dir, repository, driver, mod}
end

def create_resources
  # Prepare models, set working dir
  _, repository, driver, mod = setup

  # Clone, compile
  ACAEngine::Core::ResourceManager.instance(testing: true).start { }

  {repository, driver, mod}
end

class DiscoveryMock < HoundDog::Discovery
  def own_node?(key : String) : Bool
    true
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
