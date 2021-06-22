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
      begin
        response = yield client
      ensure
        client.connection.close
      end

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

    protected getter! connection : HTTP::Client

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

    struct DriverCommit < BaseResponse
      getter commit : String
      getter date : String
      getter author : String
      getter subject : String
    end

    # Returns the commits for a particular driver
    def driver(driver_id : String, repository : String, count : Int32? = nil)
      params = HTTP::Params{"repository" => repository}
      params["count"] = count.to_s if count

      response = get("/drivers/#{URI.encode_www_form(driver_id)}?#{params}")
      Array(DriverCommit).from_json(response.body)
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

    def branches?(repository : String)
      begin
        reponse = get("/drivers/#{repository}/branches")
      rescue e : Core::ClientError
        return if e.status_code == 404
        raise e
      end
      Array(String).from_json(reponse.body)
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

    struct Loaded < BaseResponse
      alias Processes = Hash(String, Array(String))

      getter edge : Hash(String, Processes) = {} of String => PlaceOS::Core::Client::Loaded::Processes
      getter local : Processes = PlaceOS::Core::Client::Loaded::Processes.new { |h, k| h[k] = [] of String }
    end

    # Returns the loaded modules on the node
    def loaded
      response = get("/status/loaded")
      Loaded.from_json(response.body)
    end

    # Status
    ###########################################################################

    struct CoreStatus < BaseResponse
      struct Error < BaseResponse
        getter name : String
        getter reason : String
      end

      struct Count < BaseResponse
        getter modules : Int32
        getter drivers : Int32
      end

      struct RunCount < BaseResponse
        getter local : Count
        getter edge : Hash(String, Count)
      end

      getter available_repositories : Array(String)
      getter unavailable_repositories : Array(Error)
      getter compiled_drivers : Array(String)
      getter unavailable_drivers : Array(Error)
      getter run_count : RunCount
    end

    # Core status
    def core_status : CoreStatus
      response = get("/status")
      CoreStatus.from_json(response.body)
    end

    def version : PlaceOS::Model::Version
      PlaceOS::Model::Version.from_json(get("/version").body)
    end

    struct Load < BaseResponse
      getter local : SystemLoad
      getter edge : Hash(String, SystemLoad)
    end

    struct SystemLoad < BaseResponse
      getter hostname : String
      getter cpu_count : Int32
      getter core_cpu : Float64
      getter total_cpu : Float64
      getter memory_total : Int64
      getter memory_usage : Int64
      getter core_memory : Int64
    end

    # Details about machine load
    def core_load : Load
      response = get("/status/load")
      Load.from_json(response.body)
    end

    struct DriverStatus < BaseResponse
      struct Metadata < BaseResponse
        getter running : Bool = false
        getter module_instances : Int32 = -1
        getter last_exit_code : Int32 = -1
        getter launch_count : Int32 = -1
        getter launch_time : Int64 = -1

        getter percentage_cpu : Float64? = nil
        getter memory_total : Int64? = nil
        getter memory_usage : Int64? = nil

        def initialize
        end
      end

      getter local : Metadata? = nil
      getter edge : Hash(String, Metadata?) = {} of String => PlaceOS::Core::Client::DriverStatus::Metadata?

      def initialize
      end
    end

    # Driver status
    def driver_status(path : String) : DriverStatus
      response = get("/status/driver?path=#{path}")
      DriverStatus.from_json(response.body)
    rescue e : Core::ClientError
      DriverStatus.new
    end

    # Chaos
    ###########################################################################

    def terminate(path : String) : Bool
      post("/chaos/terminate?path=#{path}").success?
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
