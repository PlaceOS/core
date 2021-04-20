require "placeos-compiler/compiler"
require "placeos-compiler/helper"

require "./helper"

module PlaceOS::Core
  describe Compilation, tags: "resource" do
    it "compiles drivers" do
      # Set up a temporary directory
      _, repository, driver, _ = setup

      # Clone driver repository
      PlaceOS::Compiler.clone_and_install(
        repository: repository.folder_name,
        repository_uri: repository.uri,
      )

      # Commence compilation
      compiler = Compilation.new
      compiler.process_resource(:created, driver).success?.should be_true

      driver.reload!

      PlaceOS::Compiler::Helper.compiled?(driver.file_name, driver.commit, driver.id.not_nil!).should be_true
      compiler.stop
    end
  end
end
