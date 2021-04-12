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

# Allow signals to change the log level at run-time
logging = Proc(Signal, Nil).new do |signal|
  log_backend = PlaceOS::LogBackend.log_backend

  prod_log_level = PlaceOS::Core.production? ? Log::Severity::Info : Log::Severity::Debug
  app_log_level = signal.usr1? ? Log::Severity::Trace : prod_log_level
  lib_log_level = signal.usr1? ? Log::Severity::Trace : Log::Severity::Info
  PlaceOS::Core::Log.info { "application log level changed to #{app_log_level}" }
  PlaceOS::Core::Log.info { "library log level changed to #{lib_log_level}" }
  ::Log.builder.bind "*", lib_log_level, log_backend
  ::Log.builder.bind "place_os.core.*", app_log_level, log_backend
  ::Log.builder.bind "action-controller.*", app_log_level, log_backend

  signal.ignore
end

# Turn on DEBUG level logging `kill -s USR1 %PID`
# Default production log levels (INFO and above) `kill -s USR2 %PID`
Signal::USR1.trap &logging
Signal::USR2.trap &logging

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
