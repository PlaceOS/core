require "./engine-core/*"

module ACAEngine::Core
  def self.start_managers
    resource_manager = ResourceManager.instance

    # In k8s we can grab the Pod information from the environment
    # https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/#use-pod-fields-as-values-for-environment-variables
    core_host = ENV["CORE_HOST"]? || "localhost"
    core_port = (ENV["CORE_PORT"]? || "3000").to_i
    module_manager = ModuleManager.instance(URI.new("http", core_host, core_port))

    # Acquire resources on startup
    resource_manager.start do
      # Start managing modules once relevant resources present
      spawn(same_thread: true) do
        module_manager.start
      end
    end
  end
end
