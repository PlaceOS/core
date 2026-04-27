require "../helper"

module PlaceOS::Core::Api
  describe Status, tags: "api" do
    client = AC::SpecHelper.client

    namespace = Status::NAMESPACE[0]
    json_headers = HTTP::Headers{
      "Content-Type" => "application/json",
    }

    after_each do
      Services.reset
    end

    describe "status/" do
      it "renders data about node" do
        _, driver, _, resource_manager = create_resources
        Services.resource_manager = resource_manager

        driver.reload!

        response = client.get(namespace, headers: json_headers)
        response.status_code.should eq 200

        status = Status::Statistics.from_json(response.body)

        status.run_count.local.modules.should eq 0
        status.run_count.local.drivers.should eq 0
        status.run_count.edge.should be_empty
      ensure
        resource_manager.try &.stop
      end

      it "returns local driver status for a running module" do
        _, driver, mod, resource_manager = create_resources
        module_manager = module_manager_mock
        Services.module_manager = module_manager
        Services.resource_manager = resource_manager
        module_manager.load_module(mod)

        driver_path = module_manager.store.driver_binary_path(driver.file_name, driver.commit).to_s
        route = "#{namespace}driver?path=#{URI.encode_path(driver_path)}"
        response = client.get(route, headers: json_headers)
        response.status_code.should eq 200

        status = Status::DriverStatus.from_json(response.body)
        status.local.should_not be_nil
        status.local.not_nil!.running.should be_true
        status.edge.should be_empty
      ensure
        module_manager.try &.stop
        resource_manager.try &.stop
      end

      it "returns machine load for local and edge runtimes" do
        _, _, _, resource_manager = create_resources
        Services.resource_manager = resource_manager
        response = client.get("#{namespace}load", headers: json_headers)
        response.status_code.should eq 200

        load = Status::MachineLoad.from_json(response.body)
        load.local.hostname.should_not be_empty
        load.local.cpu_count.should be > 0
        load.edge.should be_empty
      ensure
        resource_manager.try &.stop
      end

      it "returns loaded module mappings" do
        _, _, mod, resource_manager = create_resources
        module_manager = module_manager_mock
        Services.module_manager = module_manager
        Services.resource_manager = resource_manager
        module_manager.load_module(mod)

        response = client.get("#{namespace}loaded", headers: json_headers)
        response.status_code.should eq 200

        loaded = Status::LoadedModules.from_json(response.body)
        loaded.local.values.flatten.should contain(mod.id.as(String))
        loaded.edge.should be_empty
      ensure
        module_manager.try &.stop
        resource_manager.try &.stop
      end

      it "reports persisted edge connection visibility" do
        edge = PlaceOS::Model::Generator.edge.save!
        edge.update_fields(
          online: true,
          last_seen: Time.utc
        )

        module_manager = module_manager_mock
        Services.module_manager = module_manager
        response = client.get("#{namespace}edges", headers: json_headers)
        response.status_code.should eq 200

        body = Hash(String, Status::EdgeConnection).from_json(response.body)
        body[edge.id.as(String)].online.should be_true
        body[edge.id.as(String)].last_seen.should_not be_nil
        body[edge.id.as(String)].websocket_connected.should be_false
        body[edge.id.as(String)].snapshot_version.should be_nil
        body[edge.id.as(String)].pending_updates.should eq 0
        body[edge.id.as(String)].pending_events.should eq 0
      ensure
        module_manager.try &.stop
      end
    end
  end
end
