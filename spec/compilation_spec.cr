require "engine-drivers/compiler"
require "engine-drivers/helper"

require "./helper"

module ACAEngine::Core
  describe Compilation do
    describe "startup" do
      it "compiles drivers" do
        # Set up a temporary directory
        _, repository, driver, _ = setup

        repository_name = repository.name.as(String)
        repository_uri = repository.uri.as(String)
        driver_file = driver.file_name.as(String)

        # Clone driver repository
        ACAEngine::Drivers::Compiler.clone_and_install(
          repository: repository_name,
          repository_uri: repository_uri,
        )

        # Commence compilation
        compiler = Compilation.new.start
        compiler.processed.size.should eq 1
        compiler.processed.first.id.should eq driver.id

        driver.reload!
        ACAEngine::Drivers::Helper.compiled?(driver_file, driver.commit.not_nil!).should be_true
      end
    end
  end
end
