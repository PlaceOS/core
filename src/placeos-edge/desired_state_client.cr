require "http"
require "uri"

require "./state"

module PlaceOS::Edge
  class DesiredStateClient
    SNAPSHOT_PATH = "/api/core/v1/edge/%{edge_id}/desired_state"

    private getter edge_id : String
    private getter base_uri : URI
    private getter secret : String

    def initialize(@edge_id : String, @base_uri : URI, @secret : String)
    end

    def fetch(last_modified : Time? = nil) : State::Snapshot?
      uri = base_uri.dup
      uri.path = SNAPSHOT_PATH % {edge_id: edge_id}
      uri.query = URI::Params.encode({"api-key" => secret})

      headers = HTTP::Headers.new
      headers["If-Modified-Since"] = HTTP.format_time(last_modified) if last_modified

      response = HTTP::Client.get(uri, headers: headers)
      return nil if response.status_code == 304
      raise "failed to fetch desired state: #{response.status_code}" unless response.success?

      State::Snapshot.from_json(response.body)
    end
  end
end
