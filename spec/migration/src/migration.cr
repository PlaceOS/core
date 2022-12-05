require "micrate"
require "pg"

Micrate::DB.connection_url = ENV["PG_DATABASE_URL"]
Micrate::Cli.run
