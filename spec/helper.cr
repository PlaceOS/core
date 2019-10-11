require "spec"

# Application config
require "../src/config"

require "../src/engine-core"
require "../src/engine-core/*"

require "engine-models/spec/generator"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"
