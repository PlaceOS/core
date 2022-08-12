require "../helper"

module PlaceOS::Core::Mappings
  describe DriverModuleNames, tags: "mappings" do
    it "updates `module_names` of associated modules" do
      driver = Model::Generator.driver.save!
      Model::Generator.module(driver: driver).save!

      updated = "updated_module_name-#{random_id}"
      driver.update_fields(module_name: updated)

      DriverModuleNames.new
        .process_resource(:updated, driver)
        .success?
        .should be_true

      driver.modules.all? { |m| m.name == updated }.should be_true
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
      DriverModuleNames.new
        .process_resource(:deleted, driver)
        .skipped?
        .should be_true
    end
  end
end
