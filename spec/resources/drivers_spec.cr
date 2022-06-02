require "file_utils"
require "placeos-compiler/compiler"
require "placeos-compiler/helper"

require "../helper"

module PlaceOS::Core::Resources
  describe Drivers, tags: "resource" do
    it "compiles drivers" do
      _, driver, _ = setup

      drivers_resource = Drivers.new

      # Commence compilation
      drivers_resource.process_resource(:created, driver).success?.should be_true

      driver.reload!

      # Check that a binary was produced for the driver
      drivers_resource.binary_store.query(entrypoint: driver.file_name).should_not be_empty
    end
  end
end
