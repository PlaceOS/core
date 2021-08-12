require "./helper"
require "placeos-compiler/helper"

module PlaceOS::Core
  describe ResourceManager, tags: "resource" do
    it "loads relevant resources" do
      setup

      # Clone, compile
      cloning = Cloning.new(testing: true)
      control_system_modules = Mappings::ControlSystemModules.new(startup: false)
      resource_manager = ResourceManager.new(
        cloning: cloning,
        control_system_modules: control_system_modules,
      )

      called = false
      resource_manager.start { called = true }

      called.should be_true

      # 1 if test model already present in db, 2 if not
      # Commit hash is updated, so model might be received again during startup
      {1, 2}.any?(resource_manager.cloning.processed.size).should be_true
      {1, 2}.any?(resource_manager.drivers.processed.size).should be_true

      resource_manager.control_system_modules.processed.size.should eq 0
    ensure
      resource_manager.try &.stop
    end
  end
end
