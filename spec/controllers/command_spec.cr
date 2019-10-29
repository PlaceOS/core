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
    describe "command/:module_id/execute" do
      it "executes a command on a running module" do
        _, _, mod = create_resources
        mod_id = mod.id.as(String)
        module_manager = ModuleManager.new("localhost", 4200, DiscoveryMock.new("core"))
        module_manager.load_module(mod)

        route = "/api/core/v1/command/#{mod_id}/execute"
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
        _, _, mod = create_resources
        mod_id = mod.id.as(String)

        coord_channel = Channel(Nil).new
        messages = [] of String
        ws = HTTP::WebSocket.new("localhost", "/api/core/v1/command/#{mod_id}/debugger", 6000)
        ws.on_message do |message|
          messages << message
          coord_channel.send nil
        end

        with_server do
          ws.run
          response = curl("POST", "/api/core/v1/command/#{mod_id}/execute", HTTP::Headers{"Content-Type" => "application/json"}, EXEC_PAYLOAD)
          response.success?.should be_true
          coord_channel.receive
        end

        (messages.size > 0).should be_true
      end
    end

    pending "command/debugger"
  end
end
