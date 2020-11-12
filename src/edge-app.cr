require "option_parser"

require "./placeos-edge/config"
require "./placeos-edge/client"

module PlaceOS::Edge
  uri = PLACE_URI
  secret = CLIENT_SECRET

  # Command line options
  OptionParser.parse(ARGV.dup) do |parser|
    parser.banner = "Usage: #{APP_NAME} [arguments]"

    parser.on("-u", "--uri", "Set URI for PlaceOS instance") { |u| uri = URI.parse(u) }

    parser.on("-s", "--secret", "Set application secret") { |s| secret = s }

    parser.on("-v", "--version", "Display the application version") do
      puts "#{APP_NAME} v#{VERSION}"
      exit 0
    end

    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit 0
    end
  end

  Client.new(uri, secret).connect do
    Log.info { "started #{APP_NAME} connected to #{uri}" }
  end
end
