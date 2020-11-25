require "../helper"

require "./local_spec"

module PlaceOS::Core
  record Context,
    module : Model::Module,
    edge : Model::Edge,
    driver_path : String,
    driver_key : String

  def self.client_server(edge_id)
    client_ws, server_ws = mock_sockets
    client = Client.new(edge_id: edge_id, secret: "s3cr3t", skip_handshake: true)
    client.connect(client_ws)
    edge_manager = Edge.new(edge_id: edge_id, socket: server_ws)
    {client, edge_manager}
  end

  def self.with_edge
    with_driver do |mod, driver_path|
      if (existing_edge_id = mod.edge_id)
        edge = Model::Edge.find!(existing_edge_id)
      else
        edge = Generator.edge.save!
        mod.edge_id = edge.id.as(String)
        mod.save!
      end

      Context.new(
        module: mod,
        edge: edge,
        driver_path: driver_path,
        driver_key: Edge.path_to_key(driver_path),
      )

      client, manager = client_server(edge.id.as(String))

      yield context, client, manager
    end
  end

  describe ProcessManager::Edge do
    pending "debug" do
    end

    pending "driver_loaded?" do
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
