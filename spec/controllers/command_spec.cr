require "../helper"

# Testing pattern for controllers as follows..
# - Create the controller instance, with intended mocks
# - Create the call instance
# - Check the outcome of the request

module ACAEngine::Core
  describe Api::Command do
    describe "/:module_id/execute" do
      pending "executes a command on a running module"
    end
    describe "/:module_id/debugger" do
      pending "pipes debug output of a module"
    end
  end
end
