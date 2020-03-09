require "./core/*"

module PlaceOS::Core
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
