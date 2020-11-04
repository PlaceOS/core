require "retriable"
require "rwlock"
require "uri"

require "placeos-driver/protocol/management"

require "./constants"
require "./protocol"
require "./transport"

module PlaceOS::Edge
  class Client
    Log                = ::Log.for(self)
    WEBSOCKET_API_PATH = "/edge"

    getter binary_directory : String

    private getter transport : Transport?
    private getter! uri : URI

    def host
      uri.to_s.gsub(uri.full_path, "")
    end

    def initialize(
      uri : URI = PLACE_URI,
      secret : String = CLIENT_SECRET,
      @sequence_id : UInt64 = 0,
      @binary_directory : String = File.join(Dir.current, "/bin/drivers")
    )
      # Mutate a copy as secret is embedded in uri
      uri = uri.dup
      uri.path = WEBSOCKET_API_PATH
      uri.query = "secret=#{secret}"
      @uri = uri
    end

    # Initialize the WebSocket API
    #
    # Optionally accepts a block called after connection has been established.
    def start(initial_socket : HTTP::WebSocket? = nil)
      begin
        socket = initial_socket || HTTP::WebSocket.new(uri)
      rescue Socket::ConnectError
        Log.error { "failed to open initial connection to #{host}" }
        exit 1
      end

      Retriable.retry(on_retry: ->(_ex : Exception, _i : Int32, _e : Time::Span, _p : Time::Span) {
        Log.info { "reconnecting to #{host}" }
        socket = HTTP::WebSocket.new(uri)
      }) do
        close_channel = Channel(Nil).new

        socket.on_close do
          Log.info { "websocket to #{host} closed" }
          close_channel.close
        end

        id = if existing_transport = transport
               existing_transport.sequence_id
             else
               0_u64
             end

        @transport = Transport.new(socket, id) do |(sequence_id, request)|
          case request
          in Protocol::Server::Request
            handle_request(sequence_id, request)
          in Protocol::Client::Request
            Log.error { "unexpected request received #{request.inspect}" }
          end
        end

        spawn do
          socket.as(HTTP::WebSocket).run
        end

        while socket.closed?
          Fiber.yield
        end

        handshake

        yield

        close_channel.receive?
      end
    end

    # :ditto:
    def start(initial_socket : HTTP::WebSocket? = nil)
      start(initial_socket) { }
    end

    def handle_request(sequence_id : UInt64, request : Protocol::Server::Request)
    end

    def send_request(request : Protocol::Client::Request) : Protocol::Server::Response
      t = transport
      if t.nil?
        raise "cannot send request over closed transport"
      else
        t.send_request(request).as(Protocol::Server::Response)
      end
    end

    # TODO: fix up this client. would be good to get the correct type back
    #
    def handshake
      Retriable.retry do
        response = send_request(registration_message)
        unless response.success && response.is_a?(Protocol::Message::RegisterResponse)
          Log.warn { "failed to register to core" }
          raise "handshake failed"
        end

        response.remove_modules.each do |mod|
          unload_module(mod[:module_id])
        end

        response.remove_drivers.each do |driver|
          remove_binary(driver)
        end

        load_binaries(response.add_drivers)

        response.add_modules.each do |mod|
          load_module(mod[:module_id], mod[:key])
        end
      end
    end

    def load_binaries(binaries : Array(String))
      promises = binaries.map do |b|
        Promise.defer do
          load_binary(b)
        end
      end

      Promise.all(promises).get
    end

    # Extracts the running modules and drivers on the edge
    #
    protected def registration_message : Protocol::Message::Register
      Protocol::Message::Register.new(
        modules: modules,
        drivers: binaries,
      )
    end

    # Driver binaries
    ###########################################################################

    # List the binaries present on this client
    #
    def binaries
      Dir.children(binary_directory).reject do |file|
        file.includes?(".") || File.directory?(file)
      end
    end

    # Load binary, first checking if present locally then the server
    #
    def load_binary(key : String)
    end

    def add_binary(key : String, binary : Bytes)
      File.open(path(key), mode: "w+") do |file|
        file.write(binary)
      end
    end

    def remove_binary(key : String)
      File.delete(path(key))
      true
    rescue
      false
    end

    protected def path(key : String)
      File.join(binary_directory, key)
    end

    # Modules
    ###########################################################################

    # List the modules running on this client
    #
    def modules
      proc_manager_lock.synchronize do
        @module_proc_managers.keys
      end
    end

    def load_module(module_id : String, key : String)
      # Check for binary, request if it's not present
      # Start the module with redis hooks
    end

    def unload_module(module_id : String)
    end

    # Helpers
    ###########################################################################

    # HACK: get the driver key from the module_id
    #
    def key_for?(module_id)
      proc_manager_lock.synchronize do
        @module_proc_managers[module_id]?.try do |manager|
          @driver_proc_managers.key_for?(manager)
        end
      end
    end

    # Protocol Managers
    ###########################################################################

    def remove_driver_manager(key)
      set_driver_proc_manager(key, nil)
    end

    private getter proc_manager_lock = Mutex.new

    # Mapping from module_id to protocol manager
    @module_proc_managers : Hash(String, Driver::Protocol::Management) = {} of String => Driver::Protocol::Management

    # Mapping from driver path to protocol manager
    @driver_proc_managers : Hash(String, Driver::Protocol::Management) = {} of String => Driver::Protocol::Management

    protected def proc_manager_by_module?(module_id) : Driver::Protocol::Management?
      proc_manager_lock.synchronize do
        @module_proc_managers[module_id]?.tap do |manager|
          Log.info { "missing module manager for #{module_id}" } if manager.nil?
        end
      end
    end

    protected def proc_manager_by_driver?(driver_path) : Driver::Protocol::Management?
      proc_manager_lock.synchronize do
        @driver_proc_managers[driver_path]?.tap do |manager|
          Log.info { "missing module manager for #{driver_path}" } if manager.nil?
        end
      end
    end

    protected def set_module_proc_manager(module_id, manager : Driver::Protocol::Management?)
      proc_manager_lock.synchronize do
        if manager.nil?
          @module_proc_managers.delete(module_id)
        else
          @module_proc_managers[module_id] = manager
          manager
        end
      end
    end

    protected def set_driver_proc_manager(driver_path, manager : Driver::Protocol::Management?)
      proc_manager_lock.synchronize do
        if manager.nil?
          @driver_proc_managers.delete(driver_path)
        else
          @driver_proc_managers[driver_path] = manager
          manager
        end
      end
    end
  end
end
