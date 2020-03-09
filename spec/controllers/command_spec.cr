require "../helper"

# Testing pattern for controllers as follows..
# - Create the controller instance, with intended mocks
# - Create the call instance
# - Check the outcome of the request

module PlaceOS::Core
  EXEC_PAYLOAD = {
    __exec__:               "used_for_place_testing",
    used_for_place_testing: [] of String,
  }.to_json

  describe Api::Command, tags: "api" do
    namespace = Api::Command::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "command/:module_id/execute" do
      it "executes a command on a running module" do
        _, _, mod = create_resources
        mod_id = mod.id.as(String)
        module_manager = ModuleManager.new(CORE_URL, discovery: DiscoveryMock.new("core", uri: CORE_URL), logger: LOGGER).start
        module_manager.load_module(mod)

        route = File.join(namespace, mod_id, "execute")

        io = IO::Memory.new
        ctx = context("POST", route, json_headers, EXEC_PAYLOAD)
        ctx.route_params = {"module_id" => mod_id}
        ctx.response.output = io
        command_controller = Api::Command.new(ctx, :execute, module_manager)

        command_controller.execute

        result = begin
          String.from_json(ctx.response.output.to_s)
        rescue
          nil
        end

        result.should eq %("you can delete this file")
      end
    end

    describe "command/:module_id/debugger" do
      it "pipes debug output of a module" do
        _, _, mod = create_resources
        mod_id = mod.id.as(String)

        # Mock resources
        discovery_mock = DiscoveryMock.new("core", uri: CORE_URL)
        clustering_mock = MockClustering.new(
          uri: CORE_URL,
          discovery: discovery_mock,
          logger: LOGGER
        )
        module_manager = ModuleManager.new(
          uri: CORE_URL,
          clustering: clustering_mock,
          discovery: discovery_mock,
          logger: LOGGER,
        )

        # Load module
        module_manager.load_module(mod)

        # Create Command controller context
        route = File.join(namespace, mod_id, "debugger")
        ctx = context("GET", route)
        ctx.route_params = {"module_id" => mod_id}
        command_controller = Api::Command.new(ctx, :execute, module_manager)

        # Set up websockets on a blocking bidirectional IO
        io_server, io_client = IO::Stapled.pipe
        ws_server, ws_client = HTTP::WebSocket.new(io_server), HTTP::WebSocket.new(io_client)

        message_channel = Channel(String).new
        ws_client.on_message do |message|
          message_channel.send(message)
        end

        spawn do
          command_controller.module_debugger(ws_server)
          ws_server.run
        rescue e
          message_channel.close
          raise e
        end
        Fiber.yield

        spawn do
          ws_client.run
        rescue e
          message_channel.close
          raise e
        end
        Fiber.yield

        # Create an execute request
        route = File.join(namespace, mod_id, "execute")
        ctx = context("POST", route, json_headers, EXEC_PAYLOAD)
        ctx.route_params = {"module_id" => mod_id}
        Api::Command.new(ctx, :execute, module_manager).execute

        # Wait for a message on the debugger
        message = message_channel.receive
        message.empty?.should_not be_true
        message.should contain("this will be propagated to backoffice!")
      end
    end

    pending "command/debugger"
  end
end
