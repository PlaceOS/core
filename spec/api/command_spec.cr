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

  describe Command, tags: "api" do
    client = AC::SpecHelper.client

    namespace = Command::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "command/:module_id/execute" do
      it "executes a command on a running module" do
        _, _, mod, resource_manager = create_resources
        mod_id = mod.id.as(String)
        module_manager = module_manager_mock
        module_manager.load_module(mod)

        route = File.join(namespace, mod_id, "execute")

        response = client.post(route, headers: json_headers, body: EXEC_PAYLOAD)
        response.status_code.should eq 200

        result = response.body rescue nil

        result.should eq %("you can delete this file")
      ensure
        resource_manager.try &.stop
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
