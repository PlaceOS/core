require "placeos-driver/protocol/management"

require "./process_manager"

require "../../placeos-edge/transport"

module PlaceOS::Core
  class Processes::Edge
    include ProcessManager

    alias Transport = PlaceOS::Edge::Transport

    forward_missing_to missing

    @transport : Transport?

    protected def transport : Transport
      # HACK: fixes the indirect initialization problem
      # @transport MUST be initialized in the initializer!
      @transport.as(Transport)
    end

    def intialize(socket : HTTP::WebSocket)
      @transport = Transport.new(socket) do |request|
        handle_request(request)
      end
    end

    def handle_request(message : Protocol::Request)
    end

    protected def handshake
      # 1. edge opens a websocket connection with the REST API
      # 2. REST API consistent hashes the edge id to the right core (the core which will manage the websocket session)
      # 3. core asks edge which modules/drivers it has
      # 4. edge responds with that information
      # 5. core diffs those modules/drivers, pushes drivers the edge is missing, and unloads things that are not needed
      # 6. core asks edge to load all modules it hasn't already loaded
      # 7. core treats the edge just like any other process manager
    end

    def execute(module_id : String, payload : String)
      missing
      # make_request(API::Exec, {module_id: module_id, payload: payload}) do |result|
      #   yield result
      # end
    end

    def load(module_id : String, driver_path : String)
      missing
    end

    def unload(module_id : String)
      missing
    end

    def start(module_id : String, payload : String)
      missing
    end

    def stop(module_id : String)
      missing
    end

    def kill(driver_path : String)
      missing
    end

    # Callbacks
    ###############################################################################################

    def debug(module_id : String, &on_message : String ->)
      missing
    end

    def ignore(module_id : String, &on_message : String ->)
      missing
    end

    def on_exec(request : Request, response_callback : Request ->)
      raise "Edge modules cannot make execute requests"
    end

    # Metadata
    ###############################################################################################

    def driver_loaded?(driver_path : String) : Bool
      missing
    end

    def module_loaded?(module_id : String) : Bool
      missing
    end

    def running_drivers
      missing
    end

    def running_modules
      missing
    end

    def loaded_modules
      missing
    end

    def system_status : SystemStatus
      missing
    end

    def driver_status(driver_path : String) : DriverStatus?
      missing
    end

    def missing
      raise NotImplementedError.new("Edge has no implemented this method yet")
    end
  end
end
