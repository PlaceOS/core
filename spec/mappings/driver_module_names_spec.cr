require "../helper"

module PlaceOS::Core::Mappings
  describe DriverModuleNames, tags: "mappings", focus: true do
    it "updates `module_names` of associated modules" do
      driver = Generator.driver.save!
      Generator.module(driver: driver).save!

      updated = "updated_module_name-#{random_id}"
      driver.module_name = updated

      DriverModuleNames.new
        .process_resource(:updated, driver)
        .success?
        .should be_true

      driver.modules.all? { |m| m.module_name == updated }.should be_true
    end

    it "ignores creates" do
      driver = Model::Driver.new
      DriverModuleNames.new
        .process_resource(:created, driver)
        .skipped?
        .should be_true
    end

    it "ignores deletes" do
      driver = Model::Driver.new
      ModuleNames.new
        .process_resource(:deleted, driver)
        .skipped?
        .should be_true
    end
  end
end
