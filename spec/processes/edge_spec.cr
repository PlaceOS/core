require "../helper"
require "./support"
require "../placeos-edge/helper"

module PlaceOS::Core::ProcessManager
  record Context,
    module : Model::Module,
    edge : Model::Edge,
    driver_path : String,
    driver_key : String

  def self.client_server(edge_id)
    client_ws, server_ws = mock_sockets
    client = ::PlaceOS::Edge::Client.new(
      secret: "s3cr3t",
      skip_handshake: true,
      ping: false
    )

    edge_manager = Edge.new(edge_id: edge_id, socket: server_ws)
    spawn do
      server_ws.run
    rescue IO::Error | Channel::ClosedError
      nil
    end
    Fiber.yield
    spawn do
      client.connect(client_ws)
    rescue IO::Error | Channel::ClosedError
      nil
    end
    Fiber.yield
    {client, edge_manager, client_ws, server_ws}
  end

  def self.with_edge(&)
    with_driver do |mod, driver_path, driver_key, _driver|
      edge = if existing_edge_id = mod.edge_id
               Model::Edge.find!(existing_edge_id)
             else
               Model::Generator.edge.save!
             end

      mod.edge_id = edge.id.as(String)
      mod.running = true
      mod.save!

      client, process_manager, client_ws, server_ws = client_server(edge.id.as(String))

      begin
        # Reconcile the desired state locally on the edge. Websocket is only used
        # for realtime traffic after this point.
        snapshot = ::PlaceOS::Edge::State::Snapshot.new(
          edge_id: edge.id.as(String),
          version: Time.utc.to_unix_ms.to_s,
          last_modified: Time.utc,
          drivers: [::PlaceOS::Edge::State::DesiredDriver.new(driver_key)],
          modules: [::PlaceOS::Edge::State::DesiredModule.new(
            module_id: mod.id.as(String),
            driver_key: driver_key,
            running: true,
            payload: ModuleManager.start_payload(mod)
          )]
        )
        client.apply_snapshot(snapshot)

        module_id = mod.id.as(String)
        deadline = Time.instant + 2.seconds
        until client.driver_loaded?(driver_key) && client.module_loaded?(module_id)
          raise "timed out waiting for edge snapshot reconciliation" if Time.instant >= deadline
          sleep 20.milliseconds
        end

        ctx = Context.new(
          module: mod,
          edge: edge,
          driver_path: driver_path,
          driver_key: driver_key,
        )

        yield ({ctx, client, process_manager})
      ensure
        client.runtime_manager.kill(driver_key) rescue nil
        client.disconnect
        process_manager.transport.disconnect rescue nil
        client_ws.close rescue nil
        server_ws.close rescue nil
      end
    end
  end

  describe Edge, tags: ["edge", "processes"] do
    it "executes requests and reports runtime status from the edge runtime" do
      with_edge do |ctx, client, pm|
        module_id = ctx.module.id.as(String)
        result, code = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:used_for_place_testing), user_id: nil)
        result.should eq %("you can delete this file")
        code.should eq 200

        pm.runtime_status.connected.should be_true
        pm.runtime_status.last_seen.should_not be_nil
        pm.edge_id.should eq(ctx.edge.id)

        client.driver_loaded?(ctx.driver_key).should be_true
        client.module_loaded?(module_id).should be_true
        client.driver_status(ctx.driver_key).should_not be_nil
        client.loaded_modules.should eq({ctx.driver_key => [module_id]})
      end
    end

    it "kills edge-hosted drivers from core" do
      with_edge do |ctx, client, pm|
        pid = client.protocol_manager_by_driver?(ctx.driver_key).try(&.pid).not_nil!
        Process.exists?(pid).should be_true

        pm.kill(ctx.driver_key).should be_true

        success = Channel(Nil).new
        spawn do
          while Process.exists?(pid)
            sleep 100.milliseconds
          end
          success.send nil
        end

        select
        when success.receive
          Process.exists?(pid).should be_false
        when timeout 2.seconds
          raise "timeout"
        end
      end
    end

    it "round-trips lifecycle commands over the realtime channel" do
      with_edge do |ctx, client, pm|
        module_id = ctx.module.id.as(String)

        pm.unload(module_id).should be_true

        deadline = Time.instant + 2.seconds
        until !client.module_loaded?(module_id)
          raise "timed out waiting for edge unload" if Time.instant >= deadline
          sleep 20.milliseconds
        end

        pm.load(module_id, ctx.driver_key).should be_true
        pm.start(module_id, ModuleManager.start_payload(ctx.module)).should be_true

        deadline = Time.instant + 2.seconds
        until client.module_loaded?(module_id)
          raise "timed out waiting for edge reload" if Time.instant >= deadline
          sleep 20.milliseconds
        end

        pm.stop(module_id).should be_true
        client.module_loaded?(module_id).should be_true
      end
    end

    it "fails execute cleanly when the edge disconnects" do
      with_edge do |ctx, client, pm|
        client.disconnect

        deadline = Time.instant + 2.seconds
        until !pm.runtime_status.connected
          raise "timed out waiting for edge disconnect" if Time.instant >= deadline
          sleep 20.milliseconds
        end

        error = expect_raises(PlaceOS::Driver::RemoteException) do
          pm.execute(
            module_id: ctx.module.id.as(String),
            payload: ModuleManager.execute_payload(:used_for_place_testing),
            user_id: nil
          )
        end

        error.message.to_s.should contain("is not connected")
        error.code.should eq 503
      end
    end
  end
end
