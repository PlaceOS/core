require "http"
require "uri"
require "json"

module ACAEngine::Core
  class Client
    # Core base
    BASE_PATH = "/api/core"
    getter core_version : String = "v1"

    # Set the request_id on the client
    property request_id : String? = nil

    Habitat.create do
      setting host : String = ENV["CORE_HOST"]? || "localhost"
      setting port : Int32 = (ENV["CORE_PORT"]? || 3000).to_i
    end

    # Base struct for `Engine::Core` responses
    private abstract struct BaseResponse
      include JSON::Serializable
    end

    @connection : HTTP::Client?

    def initialize(
      uri : URI,
      @request_id : String? = nil,
      @core_version : String = "v1"
    )
      self.setting.host = uri.host
      self.setting.port = uri.port || 3000
      @connection = HTTP::Client.new(uri)
    end

    def initialize(
      host : String = self.settings.host,
      port : Int32 = self.settings.port,
      @request_id : String? = nil,
      @core_version : String = "v1"
    )
      @connection = HTTP::Client.new(host: host, port: port)
    end

    private def connection
      @connection.as(HTTP::Client)
    end

    # Drivers
    ###########################################################################

    # Returns drivers available
    def drivers(repository : String? = nil) : Array(String)
      params = HTTP::Params.encode({
        "repository" => repository,
      }.compact)

      response = get("/drivers?#{params}")
      Array(String).from_json(response.body)
    end

    # Returns the commits for a particular driver
    def driver(driver_id : String, repository : String? = nil, count : Int32? = nil) : Array(String)
      params = HTTP::Params.encode({
        "repository" => repository,
        "count"      => count,
      }.compact)

      response = get("/drivers/#{driver_id}?#{params}")
      Array(String).from_json(response.body)
    end

    # Command
    ###########################################################################

    # Returns the JSON response of executing a method on module
    def execute(module_id : String, function_name : String | Symbol, arguments : NamedTuple | Array | Hash)
      payload = {
        :__exec__     => function_name,
        function_name => arguments,
      }.to_json
      post("/command/#{module_id}/execute", payload).body
    end

    # Grab the STDOUT of a module process
    #
    # Sets up a websocket connection with core, and forwards messages to captured block
    def debug(module_id : String, & : String ->)
      headers = HTTP::Headers.new({"X-Request-ID" => request_id}.compact)

      socket = HTTP::WebSocket.new(
        host: self.setting.host,
        path: "#{BASE_PATH}/#{core_version}/command/#{module_id}/debugger",
        port: self.setting.port,
        headers: headers,
      )
      socket.on_message { |message| yield message }
      socket.run
    end

    # Status
    ###########################################################################

    struct CoreStatus < BaseResponse
      alias Error = NamedTuple(name: String, reason: String)

      getter compiled_drivers : Array(String)
      getter available_repositories : Array(String)
      getter running_drivers : Array(String)
      getter module_instances : Array(String)
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
      getter core_cpu : Float32
      getter total_cpu : Float32
      getter memory_total : Int32
      getter memory_usage : Int32
      getter core_memory : Int32
    end

    # Details about machine load
    def core_load : CoreLoad
      response = get("/load")
      CoreLoad.from_json(response.body)
    end

    struct DriverStatus < BaseResponse
      getter running : Bool
      getter module_instances : Array(String)
      getter last_exit_code : Int32
      getter launch_count : Int32
      getter launch_time : Int32

      getter percentage_cpu : Float32?
      getter memory_total : Int32?
      getter memory_usage : Float32?
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
        path = "#{BASE_PATH}/#{core_version}/#{path}"
        response = connection.{{method.id}}(path, headers, body)
        raise Core::ClientErrror.from_response(response) unless response.success?

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
          raise Core::ClientError.from_response(response) unless response.success?
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
