require "../helper"

module PlaceOS::Core::Mappings
  class Mock < Resources::Modules
    FAILS_TO_REFRESH = "fails-to-refresh"

    def self.failing_id
      "mod-#{Random::DEFAULT.hex(6)}-#{FAILS_TO_REFRESH}"
    end

    def refresh_module(mod)
      raise "mocked refresh error" if mod.id.as(String).ends_with? FAILS_TO_REFRESH
      true
    end
  end

  describe ControlSystemModules, tags: "mappings" do
    describe ".update_mapping" do
      it "ignores systems not mapped to node" do
        control_system = Model::Generator.control_system
        control_system.id = DiscoveryMock::DOES_NOT_MAP
        control_system_modules = ControlSystemModules.new(module_manager: module_manager_mock, startup: false)
        control_system_modules.process_resource(:updated, control_system).skipped?.should be_true
      end

      it "updates mappings regardless of refresh failures" do
        device_driver = Model::Generator.driver(:device).save!
        logic_driver = Model::Generator.driver(:logic).save!

        device_modules = (0...2).map do
          m = Model::Generator.module(device_driver)
          m.custom_name = "device"
          m.save!
        end

        cs = Model::Generator.control_system
        cs.modules = device_modules.compact_map &.id
        cs.save!

        borked = Model::Generator.module(logic_driver, cs)
        borked._new_flag = true
        borked.id = Mock.failing_id
        borked.custom_name = "logic"
        borked.save!

        storage = Driver::RedisStorage.new(cs.id.as(String), "system")
        storage["logic/1"] = borked.id
        # Place "device" modules in opposite order
        storage["device/1"] = device_modules[1].id
        storage["device/2"] = device_modules[0].id
        storage["device/3"] = "doesn't exist"

        ControlSystemModules.update_mapping(
          cs,
          startup: true,
          module_manager: Mock.new(CORE_URL),
        ).success?.should be_true

        storage["logic/1"]?.should eq borked.id
        storage["device/1"]?.should eq device_modules[0].id
        storage["device/2"]?.should eq device_modules[1].id
        storage["device/3"]?.should be_nil
      end
    end

    describe ".set_mappings" do
      it "clears mappings before setting them" do
        cs = Model::Generator.control_system
        cs.id = UUID.random.to_s

        storage = Driver::RedisStorage.new(cs.id.as(String), "system")
        mock_key = "bar/1"
        storage[mock_key] = "foo"
        storage[mock_key].should eq "foo"

        ControlSystemModules.set_mappings(cs, nil).should eq({} of String => String)
        storage[mock_key]?.should be_nil
      end
    end

    describe ".update_logic_modules" do
      it "does not update if system is destroyed" do
        cs = Model::ControlSystem.new
        cs.destroyed = true
        ControlSystemModules.update_logic_modules(cs, module_manager_mock).should eq 0
      end

      it "returns the number of refreshed modules" do
        driver = Model::Generator.driver(:logic).save!
        cs = Model::Generator.control_system.save!

        mock_manager = Mock.new(CORE_URL)

        mods = (0...2).map do
          Model::Generator.module(driver, cs)
        end

        ControlSystemModules.update_logic_modules(cs, mock_manager).should eq 0

        mods[0].save!
        ControlSystemModules.update_logic_modules(cs, mock_manager).should eq 1

        mods[1].save!
        ControlSystemModules.update_logic_modules(cs, mock_manager).should eq 2
      end

      it "handles refresh failures" do
        driver = Model::Generator.driver(:logic).save!
        cs = Model::Generator.control_system.save!

        mock_manager = Mock.new(CORE_URL)
        okay = Model::Generator.module(driver, cs)
        okay.save!
        ControlSystemModules.update_logic_modules(cs, mock_manager).should eq 1

        fails = Model::Generator.module(driver, cs)
        fails._new_flag = true
        fails.id = Mock.failing_id
        fails.save!

        # Updated the sole good module
        ControlSystemModules.update_logic_modules(cs, mock_manager).should eq 1

        okay.destroy

        # No modules to update
        ControlSystemModules.update_logic_modules(cs, mock_manager).should eq 0
      end
    end
  end
end
