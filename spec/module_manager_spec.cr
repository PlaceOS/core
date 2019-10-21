require "./helper"

module ACAEngine::Core
  describe ModuleManager do
    describe "startup" do
      it "registers to etcd" do
        Model::Driver.clear
        Model::Module.clear
        Model::Repository.clear

        # Start module manager
        module_manager = ModuleManager.new("localhost", 4200).start

        # Check that the node is registered in etcd
        module_manager.discovery.nodes.size.should eq 1

        module_manager.discovery.unregister
        sleep 0.1

        # Check that the node is registered in etcd
        module_manager.discovery.nodes.size.should eq 0
      end

      pending "loads relevant modules" do
        # Prepare models, set working dir
        setup

        # Clone, compile
        ResourceManager.new

        # Start module manager
        module_manager = ModuleManager.new("localhost", 4200).start

        # Check that the module is loaded, and the module manager can be received
        module_manager.running_modules.should eq 1
      end
    end
  end
end
