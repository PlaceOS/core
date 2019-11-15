require "../helper"

# Testing pattern for controllers as follows..
# - Create the controller instance, with intended mocks
# - Create the call instance
# - Check the outcome of the request

module ACAEngine::Core
  EXEC_PAYLOAD = {
    __exec__:             "used_for_aca_testing",
    used_for_aca_testing: [] of String,
  }.to_json

  describe Api::Command do
    namespace = Api::Command::NAMESPACE[0]

    describe "command/:module_id/execute" do
      it "executes a command on a running module" do
        _, _, mod = create_resources
        mod_id = mod.id.as(String)
        module_manager = ModuleManager.new("localhost", 4200, DiscoveryMock.new("core"))
        module_manager.load_module(mod)

        route = File.join(namespace, mod_id, "execute")
        headers = HTTP::Headers{
          "Content-Type" => "application/json",
        }

        io = IO::Memory.new
        ctx = context("POST", route, headers, EXEC_PAYLOAD)
        ctx.route_params = {"module_id" => mod_id}
        ctx.response.output = io
        command_controller = Api::Command.new(ctx, :execute, module_manager)

        command_controller.execute
        String.from_json(ctx.response.output.to_s).should eq %("you can delete this file")
      end
    end

    pending "command/:module_id/debugger" do
      it "pipes debug output of a module" do
        with_server do
          _, _, mod = create_resources
          mod_id = mod.id.as(String)

          client = Client.new("localhost", 6000)
          message_channel = Channel(String).new

          client.execute(mod_id, :used_for_aca_testing)

          spawn do
            client.debug(mod_id) do |message|
              message_channel.send message
            end
          rescue e
            pp! e
            raise e
          end

          Fiber.yield

          begin
            client.execute(mod_id, :used_for_aca_testing)
          rescue e : Core::ClientError
            pp! e.status_code
            raise e
          end

          message = message_channel.receive
          message.should be_a String
          message.empty?.should_not be_true
        end
      end
    end

    pending "command/debugger"
  end
end
