require "uri"
require "connect-proxy"

module PlaceOS::Core
  module BuildApi
    BUILD_API_BASE = "/api/build/v1"

    # [PPT-2524]: Identifies the cluster making the request to the build service.
    # Compatible with https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/User-Agent
    USER_AGENT = "PlaceOS/#{VERSION} #{ENV["CLUSTER_NAME"]? || "unnamed"}"

    # `HTTP::Client` applies no timeouts by default, so a half-open socket (build
    # service restart, load balancer blip) parks the calling fiber forever.
    # `DriverStore` serialises binary fetches per driver, so one parked fiber
    # wedges every subsequent load of that driver until core is restarted.
    CONNECT_TIMEOUT = (ENV["BUILD_API_CONNECT_TIMEOUT"]?.try(&.to_i?) || 10).seconds
    READ_TIMEOUT    = (ENV["BUILD_API_READ_TIMEOUT"]?.try(&.to_i?) || 60).seconds

    # Upper bound on how long `compile` polls a build job. The job may still
    # complete server side — a later request will pick up the artifact — but we
    # must not hold a driver's fetch slot indefinitely waiting for it.
    COMPILE_TIMEOUT       = (ENV["BUILD_API_COMPILE_TIMEOUT"]?.try(&.to_i?) || 600).seconds
    COMPILE_POLL_INTERVAL = 5.seconds

    # Builds the default headers sent with every build service request.
    def self.default_headers : HTTP::Headers
      HTTP::Headers{"User-Agent" => USER_AGENT}
    end

    # Yields a client pointed at the build service with timeouts applied,
    # closing it once the block returns.
    def self.with_client(&)
      client = ConnectProxy::HTTPClient.new(URI.parse(Core.build_host))
      client.connect_timeout = CONNECT_TIMEOUT
      client.read_timeout = READ_TIMEOUT
      begin
        yield client
      ensure
        client.close rescue nil
      end
    end

    def self.metadata(file_name : String, commit : String, branch : String, uri : String)
      file_name = URI.encode_www_form(file_name)
      with_client do |client|
        path = "#{BUILD_API_BASE}/metadata/#{file_name}"
        params = URI::Params.encode({"url" => uri, "branch" => branch, "commit" => commit})
        rep = client.get("#{path}?#{params}", headers: default_headers)
        Log.debug { {message: "Getting driver metadata. Server respose: #{rep.status_code}", file_name: file_name, commit: commit, branch: branch} }
        rep
      end
    end

    def self.defaults(file_name : String, commit : String, branch : String, uri : String)
      file_name = URI.encode_www_form(file_name)
      with_client do |client|
        path = "#{BUILD_API_BASE}/defaults/#{file_name}"
        params = URI::Params.encode({"url" => uri, "branch" => branch, "commit" => commit})
        rep = client.get("#{path}?#{params}", headers: default_headers)
        Log.debug { {message: "Getting driver defaults. Server respose: #{rep.status_code}", file_name: file_name, commit: commit, branch: branch} }
        rep
      end
    end

    def self.compiled?(file_name : String, commit : String, branch : String, uri : String)
      file_name = URI.encode_www_form(file_name)
      with_client do |client|
        path = "#{BUILD_API_BASE}/#{Core::ARCH}/compiled/#{file_name}"
        params = URI::Params.encode({"url" => uri, "branch" => branch, "commit" => commit})
        rep = client.get("#{path}?#{params}", headers: default_headers)
        Log.debug { {message: "Checking if driver is compiled?. Server respose: #{rep.status_code}", file_name: file_name, commit: commit, branch: branch, server_rep: rep.body} }
        rep
      end
    end

    def self.compile(file_name : String, url : String, commit : String, branch : String, force : Bool, username : String? = nil, password : String? = nil, fetch : Bool = true)
      file_name = URI.encode_www_form(file_name)
      headers = default_headers
      headers["X-Git-Username"] = username.not_nil! unless username.nil?
      headers["X-Git-Password"] = password.not_nil! unless password.nil?

      resp = with_client do |client|
        path = "#{BUILD_API_BASE}/#{Core::ARCH}/#{file_name}"
        params = URI::Params.encode({"url" => url, "branch" => branch, "commit" => commit, "force" => force.to_s})
        request_uri = "#{path}?#{params}"
        rep = client.post(request_uri, headers: headers)
        Log.debug { {message: "Build URL host : #{client.host}, URI: #{request_uri} . Server response: #{rep.status_code}", server_resp: rep.body} }
        rep
      end

      raise "Build API returned #{resp.status_code} while 202 was expected. Returned error: #{resp.body}" unless resp.status_code == 202
      link = resp.headers["Content-Location"] rescue raise "Build API returned invalid response, missing Content-Location header"

      task = JSON.parse(resp.body).as_h
      deadline = Time.instant + COMPILE_TIMEOUT
      loop do
        resp = with_client do |client|
          rep = client.get(link, headers: default_headers)
          Log.debug { {message: "Invoked request: URI: #{link} . Server response: #{rep.status_code}", server_resp: rep.body} }
          rep
        end

        raise "Returned invalid response code: #{resp.status_code}, #{link}, resp: #{resp.body}" unless resp.success? || resp.status_code == 303
        task = JSON.parse(resp.body).as_h
        break if task["state"].in?("cancelled", "error", "done")

        # Never poll forever: an abandoned job would otherwise pin the caller
        # (and, for lazy loads, the driver's fetch slot) for the life of the process.
        if Time.instant >= deadline
          raise "Build API end-point #{link} did not reach a terminal state within #{COMPILE_TIMEOUT}, last state: #{task["state"]}"
        end

        sleep COMPILE_POLL_INTERVAL
      end
      if resp.success? && task["state"].in?("cancelled", "error")
        raise task["message"].to_s
      end
      raise "Build API end-point #{link} returned invalid response code #{resp.status_code}, expected 303" unless resp.status_code == 303
      raise "Build API end-point #{link} returned invalid state #{task["state"]}, expected 'done'" unless task["state"] == "done"
      hdr = resp.headers["Location"] rescue raise "Build API returned compilation done, but missing Location URL"
      if fetch
        with_client do |client|
          client.get(hdr, headers: default_headers)
        end
      end
    end

    def self.monitor(state : String)
      with_client do |client|
        path = "#{BUILD_API_BASE}/monitor"
        params = URI::Params.encode({"state" => state})
        rep = client.get("#{path}?#{params}", headers: default_headers)
        Log.debug { {message: "Getting build service monitor. Server respose: #{rep.status_code}", state: state} }
        rep
      end
    end

    def self.cancel_job(job : String)
      with_client do |client|
        path = "#{BUILD_API_BASE}/cancel/#{URI.encode_www_form(job)}"
        rep = client.delete(path, headers: default_headers)
        Log.debug { {message: "Cancelling build job. Server respose: #{rep.status_code}", job: job} }
        rep
      end
    end
  end
end
