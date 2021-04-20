require "../helper"

module PlaceOS::Core::Mappings
  describe ModuleNames, tags: "resource" do
    it "ignores creates" do
      mod = Model::Module.new
      ModuleNames.new(ModuleManager.new("https://test.online"))
        .process_resource(:created, mod)
        .skipped?
        .should be_true
    end

    it "ignores deletes" do
      mod = Model::Module.new
      ModuleNames.new(ModuleManager.new("https://test.online"))
        .process_resource(:deleted, mod)
        .skipped?
        .should be_true
    end
  end
end
