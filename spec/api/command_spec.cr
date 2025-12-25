require "../helper"

# Testing pattern for controllers as follows..
# - Create the controller instance, with intended mocks
# - Create the call instance
# - Check the outcome of the request

module PlaceOS::Core::Api
  EXEC_PAYLOAD = {
    __exec__:               "used_for_place_testing",
    used_for_place_testing: [] of String,
  }.to_json

  # allow injecting mock manager during testing
  class Command
    class_property mock_module_manager : ModuleManager? = nil
    property module_manager : ModuleManager { @@mock_module_manager || ModuleManager.instance }
  end

  describe Command, tags: "api" do
    client = AC::SpecHelper.client

    namespace = Command::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    after_each { Command.mock_module_manager = nil }

    describe "command/:module_id/execute" do
      it "executes a command on a running module" do
        _, _, mod, resource_manager = create_resources
        mod_id = mod.id.as(String)
        module_manager = module_manager_mock
        module_manager.load_module(mod)
        Command.mock_module_manager = module_manager

        route = File.join(namespace, mod_id, "execute")
        response = client.post(route, headers: json_headers, body: EXEC_PAYLOAD)
        response.status_code.should eq 200

        result = response.body rescue nil
        result.should eq %("you can delete this file")
      ensure
        resource_manager.try &.stop
      end

      it "executes a command on a lazy module (launch_on_execute)" do
        _, _, mod, resource_manager = create_resources
        mod_id = mod.id.as(String)

        # Set module as lazy-load
        mod.launch_on_execute = true
        mod.running = true
        mod.save!

        module_manager = module_manager_mock
        # Register as lazy (don't spawn driver)
        module_manager.load_module(mod)
        Command.mock_module_manager = module_manager

        # Verify driver is not spawned
        module_manager.local_processes.module_loaded?(mod_id).should be_false
        module_manager.lazy_module?(mod_id).should be_true

        # Execute should work (will spawn driver on demand)
        route = File.join(namespace, mod_id, "execute")
        response = client.post(route, headers: json_headers, body: EXEC_PAYLOAD)
        response.status_code.should eq 200

        result = response.body rescue nil
        result.should eq %("you can delete this file")
      ensure
        resource_manager.try &.stop
      end

      it "returns 404 for non-lazy module that is not loaded" do
        _, _, mod = setup(role: PlaceOS::Model::Driver::Role::Service)
        mod_id = mod.id.as(String)

        # Don't load the module, but it's not lazy either
        module_manager = module_manager_mock
        Command.mock_module_manager = module_manager

        route = File.join(namespace, mod_id, "execute")
        response = client.post(route, headers: json_headers, body: EXEC_PAYLOAD)
        response.status_code.should eq 404
      ensure
        module_manager.try &.stop
      end
    end

    describe "command/:module_id/debugger" do
      it "pipes debug output of a module" do
        _, _, mod, resource_manager = create_resources
        mod_id = mod.id.as(String)

        # Mock resources
        module_manager = module_manager_mock

        # Load module
        module_manager.load_module(mod)
        Command.mock_module_manager = module_manager

        # Create Command controller context
        route = File.join(namespace, mod_id, "debugger")
        ws_client = client.establish_ws(route)

        message_channel = Channel(String).new
        ws_client.on_message do |m|
          message_channel.send(m)
        end

        spawn do
          ws_client.run
        rescue e
          message_channel.close
          raise e
        end
        Fiber.yield

        # Create an execute request
        route = File.join(namespace, mod_id, "execute")
        response = client.post(route, headers: json_headers, body: EXEC_PAYLOAD)
        response.status_code.should eq 200

        # Wait for messages on the debugger
        messages = [] of String
        2.times do
          select
          when message = message_channel.receive
            messages << message
          when timeout 2.seconds
            break
          end
        end

        messages.should contain %([1,"this will be propagated to backoffice!"])
      ensure
        resource_manager.try &.stop
      end
    end

    pending "command/debugger"
  end
end
