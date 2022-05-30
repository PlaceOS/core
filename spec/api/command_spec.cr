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
    namespace = Command::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    describe "command/:module_id/execute" do
      it "executes a command on a running module", focus: true do
        _, _, mod, resource_manager = create_resources(use_head: false)
        mod_id = mod.id.as(String)
        module_manager = module_manager_mock
        module_manager.load_module(mod)

        puts "\n<<<<<<<<<<"

        route = File.join(namespace, mod_id, "execute")

        io = IO::Memory.new
        ctx = context("POST", route, json_headers, EXEC_PAYLOAD)
        ctx.route_params = {"module_id" => mod_id}
        ctx.response.output = io
        command_controller = Command.new(ctx, :execute, module_manager)

        command_controller.execute

        ctx.response.status_code.should eq 200

        result = ctx.response.output.to_s rescue nil

        result.should eq %("you can delete this file")
      ensure
        resource_manager.try &.stop
      end
    end

    describe "command/:module_id/debugger" do
      it "pipes debug output of a module" do
        _, _, mod, resource_manager = create_resources(use_head: false)
        mod_id = mod.id.as(String)

        # Mock resources
        module_manager = module_manager_mock

        # Load module
        module_manager.load_module(mod)

        # Create Command controller context
        route = File.join(namespace, mod_id, "debugger")
        ctx = context("GET", route)
        ctx.route_params = {"module_id" => mod_id}
        command_controller = Command.new(ctx, :execute, module_manager)

        # Set up websockets on a blocking bidirectional IO
        io_server, io_client = IO::Stapled.pipe
        ws_server, ws_client = HTTP::WebSocket.new(io_server), HTTP::WebSocket.new(io_client)

        message_channel = Channel(String).new
        ws_client.on_message do |m|
          message_channel.send(m)
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
        Command.new(ctx, :execute, module_manager).execute

        ctx.response.status_code.should eq 200

        # Wait for a message on the debugger
        message = message_channel.receive
        message.empty?.should_not be_true
        message.should contain("this will be propagated to backoffice!")
      ensure
        resource_manager.try &.stop
      end
    end

    pending "command/debugger"
  end
end
