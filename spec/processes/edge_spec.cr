require "../helper"

require "./local_spec"

module PlaceOS::Core::ProcessManager
  record Context,
    module : Model::Module,
    edge : Model::Edge,
    driver_path : String,
    driver_key : String

  def self.client_server(edge_id)
    client_ws, server_ws = mock_sockets
    client = ::PlaceOS::Edge::Client.new(edge_id: edge_id, secret: "s3cr3t", skip_handshake: true)
    client.connect(client_ws)
    edge_manager = Edge.new(edge_id: edge_id, socket: server_ws)
    {client, edge_manager}
  end

  def self.with_edge
    with_driver do |mod, driver_path, driver|
      if mod.role.logic? || mod.control_system_id
        mod = Model::Generator.module(driver: driver)
        mod.role = Model::Driver::Role::Service
        mod.control_system_id = nil
        mod.save!
      end

      if (existing_edge_id = mod.edge_id)
        edge = Model::Edge.find!(existing_edge_id)
      else
        edge = Model::Generator.edge.save!
        mod.edge_id = edge.id.as(String)
        mod.save!
      end

      ctx = Context.new(
        module: mod,
        edge: edge,
        driver_path: driver_path,
        driver_key: Edge.path_to_key(driver_path),
      )

      client, process_manager = client_server(edge.id.as(String))

      yield ({ctx, client, process_manager})
    end
  end

  describe Edge do
    pending "debug" do
    end

    pending "driver_loaded?" do
      it "confirms a driver is loaded" do
        with_edge do |ctx, client, pm|
          pm.load(module_id: "mod", driver_path: ctx.driver_path)
          client.driver_loaded?(ctx.driver_path).should be_true
          pm.driver_loaded?(ctx.driver_path).should be_true
        end
      end

      it "confirms a driver is not loaded" do
        with_edge do |_ctx, client, pm|
          pm.driver_loaded?("does-not-exist").should be_false
          client.driver_loaded?("does-not-exist").should be_false
        end
      end
    end

    pending "driver_status" do
    end

    pending "execute" do
    end

    pending "ignore" do
    end

    pending "kill" do
    end

    pending "load" do
    end

    pending "loaded_modules" do
    end

    pending "module_loaded?" do
    end

    pending "on_exec" do
    end

    pending "run_count" do
    end

    pending "save_setting" do
    end

    pending "start" do
    end

    pending "stop" do
    end

    pending "system_status" do
    end

    pending "unload" do
    end
  end
end
