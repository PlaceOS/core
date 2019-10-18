require "spec"

# Application config
require "../src/config"

require "../src/engine-core"
require "../src/engine-core/*"

require "engine-models/spec/generator"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"

def get_temp
  "#{Dir.tempdir}/core-spec-#{UUID.random}"
end

# To reduce the run-time of the very setup heavy specs.
# - Use teardown if you need to clear a temporary repository
# - Use setup(fresh: true) if you require a clean working directory

TEMP_DIR = get_temp

# Remove the shared test directory
Spec.after_suite &->teardown

# Set up a temporary directory
def set_temporary_working_directory(fresh : Bool = false) : String
  temp_dir = fresh ? get_temp : TEMP_DIR
  ACAEngine::Drivers::Compiler.bin_dir = "#{temp_dir}/bin"
  ACAEngine::Drivers::Compiler.drivers_dir = "#{temp_dir}/repositories/drivers"
  ACAEngine::Drivers::Compiler.repository_dir = "#{temp_dir}/repositories"

  temp_dir
end

def teardown(temp_dir = TEMP_DIR)
  `rm -rf #{temp_dir}`
end

def setup(fresh : Bool = false)
  # Set up a temporary directory
  temp_dir = set_temporary_working_directory(fresh)

  # Create models
  ACAEngine::Model::Repository.clear
  ACAEngine::Model::Driver.clear
  ACAEngine::Model::Module.clear

  # Repository metadata
  repository_uri = "https://github.com/aca-labs/private-crystal-engine-drivers"
  repository_name = repository_folder_name = "drivers"

  repository = ACAEngine::Model::Generator.repository(type: ACAEngine::Model::Repository::Type::Driver)
  repository.uri = repository_uri
  repository.name = repository_name
  repository.folder_name = repository_folder_name
  repository.save!

  driver = ACAEngine::Model::Driver.new(
    name: "spec_helper",
    role: ACAEngine::Model::Driver::Role::Logic,
    commit: "head",
    version: SemanticVersion.new(major: 1, minor: 0, patch: 0),
    module_name: "PrivateHelper",
    file_name: "drivers/aca/private_helper.cr",
  )

  driver.repository = repository
  driver.save!

  mod = ACAEngine::Model::Generator.module(driver: driver).save!

  {temp_dir, repository, driver, mod}
end
