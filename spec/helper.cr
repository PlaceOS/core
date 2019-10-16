require "spec"

# Application config
require "../src/config"

require "../src/engine-core"
require "../src/engine-core/*"

require "engine-models/spec/generator"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"

# Set up a temporary directory
temp_dir = "#{Dir.current}/temp-#{UUID.random}"
ACAEngine::Drivers::Compiler.bin_dir = "#{temp_dir}/bin"
ACAEngine::Drivers::Compiler.drivers_dir = "#{temp_dir}/repositories/drivers"
ACAEngine::Drivers::Compiler.repository_dir = "#{temp_dir}/repositories"
