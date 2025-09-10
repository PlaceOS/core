require "uri"
require "connect-proxy"

module PlaceOS::Core
  module BuildApi
    BUILD_API_BASE = "/api/build/v1"

    def self.metadata(file_name : String, commit : String, branch : String, uri : String)
      host = URI.parse(Core.build_host)
      file_name = URI.encode_www_form(file_name)
      ConnectProxy::HTTPClient.new(host) do |client|
        path = "#{BUILD_API_BASE}/metadata/#{file_name}"
        params = URI::Params.encode({"url" => uri, "branch" => branch, "commit" => commit})
        uri = "#{path}?#{params}"
        rep = client.get(uri)
        Log.debug { {message: "Getting driver metadata. Server respose: #{rep.status_code}", file_name: file_name, commit: commit, branch: branch} }
        rep
      end
    end

    def self.defaults(file_name : String, commit : String, branch : String, uri : String)
      host = URI.parse(Core.build_host)
      file_name = URI.encode_www_form(file_name)
      ConnectProxy::HTTPClient.new(host) do |client|
        path = "#{BUILD_API_BASE}/defaults/#{file_name}"
        params = URI::Params.encode({"url" => uri, "branch" => branch, "commit" => commit})
        uri = "#{path}?#{params}"
        rep = client.get(uri)
        Log.debug { {message: "Getting driver defaults. Server respose: #{rep.status_code}", file_name: file_name, commit: commit, branch: branch} }
        rep
      end
    end

    def self.compiled?(file_name : String, commit : String, branch : String, uri : String)
      host = URI.parse(Core.build_host)
      file_name = URI.encode_www_form(file_name)
      ConnectProxy::HTTPClient.new(host) do |client|
        path = "#{BUILD_API_BASE}/#{Core::ARCH}/compiled/#{file_name}"
        params = URI::Params.encode({"url" => uri, "branch" => branch, "commit" => commit})
        uri = "#{path}?#{params}"
        rep = client.get(uri)
        Log.debug { {message: "Checking if driver is compiled?. Server respose: #{rep.status_code}", file_name: file_name, commit: commit, branch: branch, server_rep: rep.body} }
        rep
      end
    end

    def self.compile(file_name : String, url : String, commit : String, branch : String, force : Bool, username : String? = nil, password : String? = nil, fetch : Bool = true)
      host = URI.parse(Core.build_host)
      file_name = URI.encode_www_form(file_name)
      headers = HTTP::Headers.new
      headers["X-Git-Username"] = username.not_nil! unless username.nil?
      headers["X-Git-Password"] = password.not_nil! unless password.nil?

      resp = ConnectProxy::HTTPClient.new(host) do |client|
        path = "#{BUILD_API_BASE}/#{Core::ARCH}/#{file_name}"
        params = URI::Params.encode({"url" => url, "branch" => branch, "commit" => commit, "force" => force.to_s})
        uri = "#{path}?#{params}"
        rep = client.post(uri, headers: headers)
        Log.debug { {message: "Build URL host : #{client.host}, URI: #{uri} . Server response: #{rep.status_code}", server_resp: rep.body} }
        rep
      end

      raise "Build API returned #{resp.status_code} while 202 was expected. Returned error: #{resp.body}" unless resp.status_code == 202
      link = resp.headers["Content-Location"] rescue raise "Build API returned invalid response, missing Content-Location header"

      task = JSON.parse(resp.body).as_h
      loop do
        resp = ConnectProxy::HTTPClient.new(host) do |client|
          rep = client.get(link)
          Log.debug { {message: "Invoked request: URI: #{link} . Server response: #{rep.status_code}", server_resp: rep.body} }
          rep
        end

        raise "Returned invalid response code: #{resp.status_code}, #{link}, resp: #{resp.body}" unless resp.success? || resp.status_code == 303
        task = JSON.parse(resp.body).as_h
        break if task["state"].in?("cancelled", "error", "done")
        sleep 5.seconds
      end
      if resp.success? && task["state"].in?("cancelled", "error")
        raise task["message"].to_s
      end
      raise "Build API end-point #{link} returned invalid response code #{resp.status_code}, expected 303" unless resp.status_code == 303
      raise "Build API end-point #{link} returned invalid state #{task["state"]}, expected 'done'" unless task["state"] == "done"
      hdr = resp.headers["Location"] rescue raise "Build API returned compilation done, but missing Location URL"
      if fetch
        ConnectProxy::HTTPClient.new(host) do |client|
          client.get(hdr)
        end
      end
    end

    def self.monitor(state : String)
      host = URI.parse(Core.build_host)
      ConnectProxy::HTTPClient.new(host) do |client|
        path = "#{BUILD_API_BASE}/monitor"
        params = URI::Params.encode({"state" => state})
        uri = "#{path}?#{params}"
        rep = client.get(uri)
        Log.debug { {message: "Getting build service monitor. Server respose: #{rep.status_code}", state: state} }
        rep
      end
    end

    def self.cancel_job(job : String)
      host = URI.parse(Core.build_host)
      ConnectProxy::HTTPClient.new(host) do |client|
        path = "#{BUILD_API_BASE}/cancel/#{URI.encode_www_form(job)}"
        rep = client.delete(path)
        Log.debug { {message: "Cancelling build job. Server respose: #{rep.status_code}", job: job} }
        rep
      end
    end
  end
end
