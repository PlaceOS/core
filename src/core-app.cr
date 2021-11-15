require "option_parser"

# Server defaults
port = 3000
host = "127.0.0.1"
cluster = false
process_count = 1

# Command line options
OptionParser.parse(ARGV.dup) do |parser|
  parser.banner = "Usage: #{PlaceOS::Core::APP_NAME} [arguments]"

  parser.on("-b HOST", "--bind=HOST", "Specifies the server host") { |h| host = h }
  parser.on("-p PORT", "--port=PORT", "Specifies the server port") { |p| port = p.to_i }

  parser.on("-w COUNT", "--workers=COUNT", "Specifies the number of processes to handle requests") do |w|
    cluster = true
    process_count = w.to_i
  end

  parser.on("-r", "--routes", "List the application routes") do
    ActionController::Server.print_routes
    exit 0
  end

  parser.on("-e", "--env", "List the application environment") do
    ENV.accessed.sort.each &->puts(String)
    exit 0
  end

  parser.on("-v", "--version", "Display the application version") do
    puts "#{PlaceOS::Core::APP_NAME} v#{PlaceOS::Core::VERSION}"
    exit 0
  end

  parser.on("-c URL", "--curl=URL", "Perform a basic health check by requesting the URL") do |url|
    begin
      response = HTTP::Client.get url
      exit 0 if (200..499).includes? response.status_code
      puts "health check failed, received response code #{response.status_code}"
      exit 1
    rescue error
      error.inspect_with_backtrace(STDOUT)
      exit 2
    end
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit 0
  end
end

require "./config"

# Load the routes
PlaceOS::Core::Log.info { "launching #{PlaceOS::Core::APP_NAME} v#{PlaceOS::Core::VERSION} (#{PlaceOS::Core::BUILD_COMMIT} @ #{PlaceOS::Core::BUILD_TIME})" }

server = ActionController::Server.new(port, host)

# Start clustering
server.cluster(process_count, "-w", "--workers") if cluster

terminate = Proc(Signal, Nil).new do |signal|
  puts " > terminating gracefully"
  spawn(same_thread: true) { server.close }
  signal.ignore
end

# Detect ctr-c to shutdown gracefully
Signal::INT.trap &terminate
# Docker containers use the term signal
Signal::TERM.trap &terminate

# Wait for etcd, redis, and rethinkdb to be ready
PlaceOS::Core.wait_for_resources

spawn(same_thread: true) do
  begin
    PlaceOS::Core.start_managers
  rescue error
    PlaceOS::Core::Log.error { "startup failed" }
    server.close
    raise error
  end
end

# Start the server
server.run do
  PlaceOS::Core::Log.info { "listening on #{server.print_addresses}" }
end

# Shutdown message
PlaceOS::Core::Log.info { "#{PlaceOS::Core::APP_NAME} leaps through the veldt" }
