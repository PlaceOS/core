require "placeos-driver/protocol/management"

require "./process_manager"

module PlaceOS::Core
  class Processes::Edge
    include ProcessManager

    forward_missing_to missing

    def execute(module_id : String, payload : String)
      missing
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

    def missing
      raise NotImplementedError.new("Edge has no implemented this method yet")
    end
  end
end
