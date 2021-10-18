require "./helper"
require "placeos-compiler/helper"

module PlaceOS::Core
  describe Resources::Manager, tags: "resource" do
    it "loads relevant resources" do
      setup

      control_system_modules = Mappings::ControlSystemModules.new(startup: false)
      resource_manager = Resources::Manager.new(
        control_system_modules: control_system_modules,
      )

      called = false
      resource_manager.start { called = true }

      called.should be_true

      # 1 if test model already present in db, 2 if not
      # Commit hash is updated, so model might be received again during startup
      {1, 2}.any?(resource_manager.drivers.processed.size).should be_true

      resource_manager.control_system_modules.processed.size.should eq 0
    ensure
      resource_manager.try &.stop
    end
  end
end
