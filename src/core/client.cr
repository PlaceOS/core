require "http"
require "json"
require "mutex"
require "uri"

require "./error"

module PlaceOS::Core
  class Client
    # Core base
    BASE_PATH    = "/api/core"
    CORE_VERSION = "v1"
    getter core_version : String = CORE_VERSION

    # Set the request_id on the client
    property request_id : String? = nil
    getter host : String = ENV["CORE_HOST"]? || "localhost"
    getter port : Int32 = (ENV["CORE_PORT"]? || 3000).to_i

    # Base struct for `Engine::Core` responses
    private abstract struct BaseResponse
      include JSON::Serializable
    end

    # A one-shot Core client
    def self.client(
      uri : URI,
      request_id : String? = nil,
      core_version : String = CORE_VERSION
    )
      client = new(uri, request_id, core_version)
      response = yield client
      client.connection.close
      response
    end

    def initialize(
      uri : URI,
      @request_id : String? = nil,
      @core_version : String = CORE_VERSION
    )
      uri_host = uri.host
      @host = uri_host if uri_host
      @port = uri.port || 3000
      @connection = HTTP::Client.new(uri)
    end

    def initialize(
      host : String? = nil,
      port : Int32? = nil,
      @request_id : String? = nil,
      @core_version : String = CORE_VERSION
    )
      @host = host if host
      @port = port if port
      @connection = HTTP::Client.new(host: @host, port: @port)
    end

    @connection : HTTP::Client?

    protected def connection
      @connection.as(HTTP::Client)
    end

    protected getter connection_lock : Mutex = Mutex.new

    def close
      connection_lock.synchronize do
        connection.close
      end
    end

    # Drivers
    ###########################################################################

    # Returns drivers available
    def drivers(repository : String) : Array(String)
      params = HTTP::Params{"repository" => repository}
      response = get("/drivers?#{params}")
      Array(String).from_json(response.body)
    end

    # Returns the commits for a particular driver
    def driver(driver_id : String, repository : String, count : Int32? = nil)
      params = HTTP::Params{"repository" => repository}
      params["count"] = count.to_s if count

      response = get("/drivers/#{URI.encode_www_form(driver_id)}?#{params}")
      Array(NamedTuple(
        commit: String,
        date: String,
        author: String,
        subject: String)).from_json(response.body)
    end

    # Returns the metadata for a particular driver
    def driver_details(file_name : String, commit : String, repository : String) : String
      params = HTTP::Params{
        "commit"     => commit,
        "repository" => repository,
      }

      response = get("/drivers/#{URI.encode_www_form(file_name)}/details?#{params}")

      # Response looks like:
      # https://github.com/placeos/driver/blob/master/docs/command_line_options.md#discovery-and-defaults
      response.body
    end

    def driver_compiled?(file_name : String, commit : String, repository : String, tag : String)
      params = HTTP::Params{
        "commit"     => commit,
        "repository" => repository,
        "tag"        => tag,
      }

      response = get("/drivers/#{URI.encode_www_form(file_name)}/compiled?#{params}")

      # Response looks like:
      # https://github.com/placeos/driver/blob/master/docs/command_line_options.md#discovery-and-defaults
      Bool.from_json(response.body)
    end

    # Command
    ###########################################################################

    # Returns the JSON response of executing a method on module
    def execute(module_id : String, method : String | Symbol, arguments : NamedTuple | Array | Hash = [] of Nil)
      payload = {
        :__exec__ => method,
        method    => arguments,
      }.to_json
      post("/command/#{module_id}/execute", body: payload).body
    end

    # Grab the STDOUT of a module process
    #
    # Sets up a websocket connection with core, and forwards messages to captured block
    def debug(module_id : String, &block : String ->)
      headers = HTTP::Headers.new
      headers["X-Request-ID"] = request_id.as(String) if request_id

      socket = HTTP::WebSocket.new(
        host: host,
        path: "#{BASE_PATH}/#{CORE_VERSION}/command/#{module_id}/debugger",
        port: port,
        headers: headers,
      )

      socket.on_message(&block)
      socket.run
    end

    def load(module_id : String)
      post("/command/#{module_id}/load").success?
    end

    # Status
    ###########################################################################

    struct CoreStatus < BaseResponse
      alias Error = NamedTuple(name: String, reason: String)
      getter compiled_drivers : Array(String)
      getter available_repositories : Array(String)
      getter running_drivers : Int32
      getter module_instances : Int32
      getter unavailable_repositories : Array(Error)
      getter unavailable_drivers : Array(Error)
    end

    # Core status
    def core_status : CoreStatus
      response = get("/status")
      CoreStatus.from_json(response.body)
    end

    struct CoreLoad < BaseResponse
      getter hostname : String
      getter cpu_count : Int32
      getter core_cpu : Float64
      getter total_cpu : Float64
      getter memory_total : Int64
      getter memory_usage : Int64
      getter core_memory : Int64
    end

    # Details about machine load
    def core_load : CoreLoad
      response = get("/load")
      CoreLoad.from_json(response.body)
    end

    struct DriverStatus < BaseResponse
      getter running : Bool
      getter module_instances : Int32
      getter last_exit_code : Int32
      getter launch_count : Int32
      getter launch_time : Int64

      getter percentage_cpu : Float64?
      getter memory_total : Int64?
      getter memory_usage : Int64?
    end

    # Driver status
    def driver_status(path : String) : DriverStatus
      response = get("/driver?path=#{path}")
      DriverStatus.from_json(response.body)
    end

    # Chaos
    ###########################################################################

    def terminate(path : String) : Bool
      post("/terminate?path=#{path}").success?
    end

    # API modem
    ###########################################################################

    {% for method in %w(get post) %}
      # Executes a {{method.id.upcase}} request on core connection.
      #
      # The response status will be automatically checked and a Engine::Core::ClientError raised if
      # unsuccessful.
      # ```
      private def {{method.id}}(path, headers : HTTP::Headers? = nil, body : HTTP::Client::BodyType? = nil)
        path = File.join(BASE_PATH, CORE_VERSION, path)

        response = connection_lock.synchronize do
          connection.{{method.id}}(path, headers, body)
        end
        raise Core::ClientError.from_response("#{@host}:#{@port}#{path}", response) unless response.success?

        response
      end

      # Executes a {{method.id.upcase}} request on the core client connection with a JSON body
      # formed from the passed `NamedTuple`.
      private def {{method.id}}(path, body : NamedTuple)
        headers = HTTP::Headers{
          "Content-Type" => "application/json"
        }
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json)
      end

      # :ditto:
      private def {{method.id}}(path, headers : HTTP::Headers, body : NamedTuple)
        headers["Content-Type"] = "application/json"
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json)
      end

      # Executes a {{method.id.upcase}} request and yields a `HTTP::Client::Response`.
      #
      # When working with endpoint that provide stream responses these may be accessed as available
      # by calling `#body_io` on the yielded response object.
      #
      # The response status will be automatically checked and a Core::ClientErrror raised if
      # unsuccessful.
      private def {{method.id}}(path, headers : HTTP::Headers? = nil, body : HTTP::Client::BodyType = nil)
        connection.{{method.id}}(path, headers, body) do |response|
          raise Core::ClientError.from_response("#{@host}:#{@port}#{path}", response) unless response.success?
          yield response
        end
      end

      # Executes a {{method.id.upcase}} request on the core client connection with a JSON body
      # formed from the passed `NamedTuple` and yields streamed response entries to the block.
      private def {{method.id}}(path, body : NamedTuple)
        headers = HTTP::Headers{
          "Content-Type" => "application/json"
        }
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json) do |response|
          yield response
        end
      end

      # :ditto:
      private def {{method.id}}(path, headers : HTTP::Headers, body : NamedTuple)
        headers["Content-Type"] = "application/json"
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json) do |response|
          yield response
        end
      end
    {% end %}
  end
end
