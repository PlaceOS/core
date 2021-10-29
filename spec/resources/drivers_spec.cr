require "file_utils"
require "placeos-compiler/compiler"
require "placeos-compiler/helper"

require "../helper"

module PlaceOS::Core::Resources
  describe Drivers, tags: "resource", focus: true do
    it "compiles drivers" do
      # Set up a temporary directory
      _, _, driver, _ = setup

      # Commence compilation
      Drivers.new.process_resource(:created, driver).success?.should be_true

      driver.reload!

      # # TODO: Update to use new executable format
      # PlaceOS::Compiler::Helper.compiled?(driver.file_name, driver.commit, driver.id.not_nil!).should be_true
    end
  end
end
