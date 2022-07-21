require "../helper"

module PlaceOS::Core::Resources
  describe SettingsUpdate, tags: "resource" do
    it "ignores versions" do
      settings = Model::Settings.new
      settings.id = "sets-version"
      settings.settings_id = "sets-parent"
      settings_update = SettingsUpdate.new(Resources::Modules.new("https:://test.online"))

      settings_update.process_resource(:created, settings).skipped?.should be_true
    end
  end
end
