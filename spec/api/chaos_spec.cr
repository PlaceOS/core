require "../helper"

module PlaceOS::Core
  describe Api::Chaos, tags: "api" do
    client = AC::SpecHelper.client
    namespace = Api::Chaos::NAMESPACE[0]

    after_each do
      Services.reset
    end

    it "chaos/terminate" do
      ProcessManager.with_driver do |mod, _driver_path, driver_key, _driver|
        module_manager = module_manager_mock
        Services.module_manager = module_manager

        module_manager.load_module(mod)
        pid = module_manager.local_processes.protocol_manager_by_driver?(driver_key).try(&.pid).not_nil!
        Process.exists?(pid).should be_true

        response = client.post("#{namespace}terminate?path=#{driver_key}")
        response.status_code.should eq 200

        success = Channel(Nil).new
        spawn do
          while Process.exists?(pid)
            sleep 50.milliseconds
          end
          success.send nil
        end

        select
        when success.receive
          Process.exists?(pid).should be_false
        when timeout 2.seconds
          raise "timeout waiting for driver terminate"
        end
      ensure
        module_manager.try &.stop
      end
    end
  end
end
