require "../helper"

module PlaceOS::Core::ProcessManager
  def self.with_driver
    _working_directory, repository, driver, mod = setup
    Cloning.clone_and_install(repository)
    result = Compiler::Helper.compile_driver(driver.file_name, repository.folder_name, driver.commit, id: driver.id)
    yield mod, result[:executable], driver
  end

  def self.test_starting(manager, mod, driver_path)
    module_id = mod.id.as(String)
    manager.load(module_id: module_id, driver_path: driver_path)
    manager.start(module_id: module_id, payload: ModuleManager.start_payload(mod))
    manager.loaded_modules.should eq({driver_path => [module_id]})
  end

  describe Local do
    with_driver do |mod, driver_path, _driver|
      describe Local::Common do
        describe "driver_loaded?" do
          it "confirms a driver is loaded" do
            pm = Local.new(discovery_mock)
            pm.load(module_id: "mod", driver_path: driver_path)
            pm.driver_loaded?(driver_path).should be_true
          end

          it "confirms a driver is not loaded" do
            Local.new(discovery_mock).driver_loaded?("does-not-exist").should be_false
          end
        end

        describe "driver_status" do
          it "returns driver status if present" do
            pm = Local.new(discovery_mock)
            pm.load(module_id: "mod", driver_path: driver_path)

            status = pm.driver_status(driver_path)
            status.should_not be_nil
          end

          it "returns nil in not present" do
            Local.new(discovery_mock).driver_status("doesntexist").should be_nil
          end
        end

        it "execute" do
          pm = Local.new(discovery_mock)
          module_id = mod.id.as(String)
          pm.load(module_id: module_id, driver_path: driver_path)
          pm.start(module_id: module_id, payload: ModuleManager.start_payload(mod))
          result = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:used_for_place_testing))
          result.should eq %("you can delete this file")
        end

        it "debug" do
          pm = Local.new(discovery_mock)
          module_id = mod.id.as(String)
          pm.load(module_id: module_id, driver_path: driver_path)
          pm.start(module_id: module_id, payload: ModuleManager.start_payload(mod))
          message_channel = Channel(String).new

          pm.debug(module_id) do |message|
            message_channel.send(message)
          end

          result = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:echo, ["hello"]))
          result.should eq %("hello")

          select
          when message = message_channel.receive
          when timeout 2.seconds
            raise "timeout"
          end

          message.should eq %([1,"hello"])
        end

        it "ignore" do
          pm = Local.new(discovery_mock)
          module_id = mod.id.as(String)
          pm.load(module_id: module_id, driver_path: driver_path)
          pm.start(module_id: module_id, payload: ModuleManager.start_payload(mod))
          message_channel = Channel(String).new

          callback = ->(message : String) do
            message_channel.send message
          end

          pm.debug(module_id, &callback)

          result = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:echo, ["hello"]))
          result.should eq %("hello")

          select
          when message = message_channel.receive
            message.should eq %([1,"hello"])
          when timeout 2.seconds
            raise "timeout"
          end

          pm.ignore(module_id, &callback)
          result = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:echo, ["hello"]))
          result.should eq %("hello")

          expect_raises(Exception) do
            select
            when message = message_channel.receive
            when timeout 0.5.seconds
              raise "timeout"
            end
          end
        end

        it "start" do
          pm = Local.new(discovery_mock)
          module_id = mod.id.as(String)
          pm.load(module_id: module_id, driver_path: driver_path)
          pm.start(module_id: module_id, payload: ModuleManager.start_payload(mod))
          pm.loaded_modules.should eq({driver_path => [module_id]})
          pm.kill(driver_path)
        end

        it "stop" do
          pm = Local.new(discovery_mock)
          pm.kill(driver_path)
          test_starting(pm, mod, driver_path)
          pm.stop(mod.id.as(String))

          sleep 0.1
          pm.loaded_modules.should eq({driver_path => [] of String})
        end

        it "system_status" do
          Local.new(discovery_mock).system_status.should be_a(SystemStatus)
        end

        it "kill" do
          pm = Local.new(discovery_mock)
          test_starting(pm, mod, driver_path)
          pid = pm.proc_manager_by_driver?(driver_path).try(&.pid).not_nil!

          Process.exists?(pid).should be_true
          pm.kill(driver_path).should be_true

          success = Channel(Nil).new

          spawn do
            while Process.exists?(pid)
              sleep 0.1
            end
            success.send nil
          end

          select
          when success.receive
            Process.exists?(pid).should be_false
          when timeout 2.seconds
            raise "timeout"
          end
        end

        it "loaded_modules" do
          pm = Local.new(discovery_mock)
          test_starting(pm, mod, driver_path)
          pm.kill(driver_path)
        end

        describe "module_loaded?" do
          it "confirms a module is loaded" do
            pm = Local.new(discovery_mock)
            pm.load(module_id: "mod", driver_path: driver_path)
            pm.module_loaded?("mod").should be_true
          end

          it "confirms a module is not loaded" do
            Local.new(discovery_mock).module_loaded?("does-not-exist").should be_false
          end
        end

        it "run_count" do
          pm = Local.new(discovery_mock)
          pm.load(module_id: "mod", driver_path: driver_path)
          pm.run_count.should eq({drivers: 1, modules: 1})
        end

        describe "unload" do
          it "removes driver if no dependent modules running" do
            path = driver_path + UUID.random.to_s
            module_id = "mod"
            File.copy(driver_path, path)

            pm = Local.new(discovery_mock)
            pm.load(module_id: module_id, driver_path: path)
            pm.driver_loaded?(path).should be_true
            pm.module_loaded?(module_id).should be_true
            pm.unload(module_id)
            pm.driver_loaded?(path).should be_false
            pm.module_loaded?(module_id).should be_false
            File.exists?(path).should be_true

            File.delete(path) rescue nil
          end

          it "keeps driver if dependent modules still running" do
            path = driver_path + UUID.random.to_s
            module0 = "mod0"
            module1 = "mod1"
            File.copy(driver_path, path)

            pm = Local.new(discovery_mock)
            pm.load(module_id: module0, driver_path: path)
            pm.load(module_id: module1, driver_path: path)
            pm.driver_loaded?(path).should be_true
            pm.module_loaded?(module0).should be_true
            pm.module_loaded?(module1).should be_true
            pm.unload(module0)
            pm.module_loaded?(module0).should be_false
            pm.module_loaded?(module1).should be_true
            pm.driver_loaded?(path).should be_true
            File.exists?(path).should be_true

            File.delete(path) rescue nil
          end
        end
      end

      it "load" do
        pm = Local.new(discovery_mock)
        pm.driver_loaded?(driver_path).should be_false
        pm.module_loaded?("mod").should be_false
        pm.load(module_id: "mod", driver_path: driver_path)
        pm.driver_loaded?(driver_path).should be_true
        pm.module_loaded?("mod").should be_true
      end

      pending "on_exec" do
      end

      pending "save_setting" do
      end
    end
  end
end
