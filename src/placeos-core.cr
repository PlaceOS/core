require "action-controller/logger"
require "log_helper"
require "./placeos-core/*"

module PlaceOS::Core
  Log         = ::Log.for(self)
  LOG_BACKEND = ActionController.default_backend

  def self.start_managers
    resource_manager = ResourceManager.instance
    module_manager = ModuleManager.instance

    # Acquire resources on startup
    resource_manager.start do
      # Start managing modules once relevant resources present
      spawn(same_thread: true) do
        module_manager.start
      end
    end
  end
end
