require "../helper"

# Testing pattern for controllers as follows..
# - Create the controller instance, with intended mocks
# - Create the call instance
# - Check the outcome of the request

module ACAEngine::Core
  describe Api::Command do
    describe "command/:module_id/execute" do
      pending "executes a command on a running module" do
        _, _, mod = create_resources
        mod_id = mod.id.as(String)
        module_manager = ModuleManager.new("localhost", 4200, DiscoveryMock.new("core"))
        module_manager.load_module(mod)

        payload = {
          __exec__:             "used_for_aca_testing",
          used_for_aca_testing: [] of String,
        }.to_json

        route = "/api/core/v1/command/#{mod_id}/execute"
        headers = HTTP::Headers{
          "Content-Type" => "application/json",
        }

        ctx = context("POST", route, headers, payload)
        ctx.route_params = {"module_id" => mod_id}
        command_controller = Api::Command.new(ctx, :execute, module_manager)

        command_controller.execute
      end
    end

    pending "command/:module_id/debugger" do
      it "pipes debug output of a module" do
        _, _, _ = create_resources
      end
    end

    pending "command/debugger"
  end
end
