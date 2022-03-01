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
    client = ::PlaceOS::Edge::Client.new(
      secret: "s3cr3t",
      skip_handshake: true,
      ping: false
    )

    edge_manager = Edge.new(edge_id: edge_id, socket: server_ws)
    spawn { server_ws.run }
    Fiber.yield
    spawn { client.connect(client_ws) }
    Fiber.yield
    {client, edge_manager}
  end

  def self.with_edge
    with_driver do |mod, driver_path, _driver|
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
        driver_key: ProcessManager.path_to_key(driver_path),
      )

      client, process_manager = client_server(edge.id.as(String))

      yield ({ctx, client, process_manager})
    end
  end

  describe Edge, tags: ["edge", "processes"] do
    it "debug" do
      with_edge do |ctx, _client, pm|
        module_id = ctx.module.id.as(String)
        pm.load(module_id: module_id, driver_key: ctx.driver_path)
        pm.start(module_id: module_id, payload: Resources::Modules.start_payload(ctx.module))

        message_channel = Channel(String).new

        pm.debug(module_id) do |message|
          message_channel.send(message)
          nil
        end

        result, code = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:echo, ["hello"]), user_id: nil)
        result.should eq %("hello")
        code.should eq 200

        select
        when message = message_channel.receive
          message.should eq %([1,"hello"])
        when timeout 2.seconds
          raise "timeout"
        end
      end
    end

    describe "driver_loaded?" do
      it "confirms a driver is loaded" do
        with_edge do |ctx, client, pm|
          pm.load(module_id: "mod", driver_key: ctx.driver_key)
          client.driver_loaded?(ctx.driver_key).should be_true
          pm.driver_loaded?(ctx.driver_key).should be_true
        end
      end

      it "confirms a driver is not loaded" do
        with_edge do |_ctx, client, pm|
          pm.driver_loaded?("does-not-exist").should be_false
          client.driver_loaded?("does-not-exist").should be_false
        end
      end
    end

    describe "driver_status" do
      it "returns driver status if present" do
        # TODO: Could do with a double check of values
        with_edge do |ctx, client, pm|
          pm.load(module_id: "mod", driver_key: ctx.driver_path)

          pm.driver_status(ctx.driver_path).should_not be_nil
          client.driver_status(ctx.driver_key).should_not be_nil
        end
      end

      it "returns nil in not present" do
        with_edge do |_ctx, client, pm|
          pm.driver_status("doesntexist").should be_nil
          client.driver_status("doesntexist").should be_nil
        end
      end
    end

    it "execute" do
      with_edge do |ctx, _client, pm|
        module_id = ctx.module.id.as(String)
        pm.load(module_id: module_id, driver_key: ctx.driver_path)
        pm.start(module_id: module_id, payload: ModuleManager.start_payload(ctx.module))
        result, code = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:used_for_place_testing), user_id: nil)
        result.should eq %("you can delete this file")
        code.should eq 200
      end
    end

    it "ignore" do
      with_edge do |ctx, _client, pm|
        module_id = ctx.module.id.as(String)
        pm.load(module_id: module_id, driver_key: ctx.driver_path)
        pm.start(module_id: module_id, payload: Resources::Modules.start_payload(ctx.module))
        message_channel = Channel(String).new

        callback = ->(message : String) do
          message_channel.send message
          nil
        end

        pm.debug(module_id, &callback)
        result, code = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:echo, ["hello"]), user_id: nil)
        result.should eq %("hello")
        code.should eq 200

        select
        when message = message_channel.receive
          message.should eq %([1,"hello"])
        when timeout 2.seconds
          raise "timeout"
        end

        pm.ignore(module_id, &callback)
        result, code = pm.execute(module_id: module_id, payload: ModuleManager.execute_payload(:echo, ["hello"]), user_id: nil)
        result.should eq %("hello")
        code.should eq 200

        expect_raises(Exception) do
          select
          when message = message_channel.receive
          when timeout 0.5.seconds
            raise "timeout"
          end
        end
      end
    end

    it "kill" do
      with_edge do |ctx, client, pm|
        test_starting(pm, ctx.module, ctx.driver_key)

        pid = client.protocol_manager_by_driver?(ctx.driver_key).try(&.pid).not_nil!

        Process.exists?(pid).should be_true
        pm.kill(ctx.driver_path).should be_true

        success = Channel(Nil).new

        spawn do
          while Process.exists?(pid)
            sleep 0.1
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

    it "load" do
      with_edge do |ctx, client, pm|
        pm.driver_loaded?(ctx.driver_path).should be_false
        pm.module_loaded?("mod").should be_false
        client.module_loaded?("mod").should be_false

        pm.load(module_id: "mod", driver_key: ctx.driver_path)

        pm.driver_loaded?(ctx.driver_path).should be_true
        client.driver_loaded?(ctx.driver_key).should be_true

        pm.module_loaded?("mod").should be_true
        client.module_loaded?("mod").should be_true
      end
    end

    it "loaded_modules" do
      with_edge do |ctx, _client, pm|
        test_starting(pm, ctx.module, ctx.driver_key)
      end
    end

    describe "module_loaded?" do
      it "confirms a module is loaded" do
        with_edge do |ctx, _client, pm|
          pm.load(module_id: "mod", driver_key: ctx.driver_path)
          pm.module_loaded?("mod").should be_true
        end
      end

      it "confirms a module is not loaded" do
        with_edge do |_ctx, _client, pm|
          pm.module_loaded?("does-not-exist").should be_false
        end
      end
    end

    it "run_count" do
      with_edge do |ctx, _client, pm|
        pm.load(module_id: "mod", driver_key: ctx.driver_path)
        pm.run_count.should eq(ProcessManager::Count.new(1, 1))
      end
    end

    pending "save_setting" do
    end

    pending "on_redis" do
    end

    it "start" do
      with_edge do |ctx, client, pm|
        module_id = ctx.module.id.as(String)
        pm.load(module_id: module_id, driver_key: ctx.driver_path)
        pm.start(module_id: module_id, payload: Resources::Modules.start_payload(ctx.module))
        pm.loaded_modules.should eq({ctx.driver_key => [module_id]})
        client.loaded_modules.should eq({ctx.driver_key => [module_id]})
        pm.kill(ctx.driver_path)
      end
    end

    it "stop" do
      with_edge do |ctx, _client, pm|
        pm.kill(ctx.driver_path)
        test_starting(pm, ctx.module, ctx.driver_key)
        pm.stop(ctx.module.id.as(String))

        sleep 0.1
        pm.loaded_modules.should eq({ctx.driver_key => [] of String})
      end
    end

    it "system_status" do
      with_edge do |_ctx, _client, pm|
        pm.system_status.should be_a(SystemStatus)
      end
    end

    describe "unload" do
      it "removes driver if no dependent modules running" do
        with_edge do |ctx, _client, pm|
          pm.system_status.should be_a(SystemStatus)
          path = ctx.driver_path + UUID.random.to_s
          module_id = "mod"
          File.copy(ctx.driver_path, path)

          pm.load(module_id: module_id, driver_key: path)
          pm.driver_loaded?(path).should be_true
          pm.module_loaded?(module_id).should be_true
          pm.unload(module_id)
          pm.driver_loaded?(path).should be_false
          pm.module_loaded?(module_id).should be_false
        end
      end

      it "keeps driver if dependent modules still running" do
        with_edge do |ctx, _client, pm|
          path = ctx.driver_path + UUID.random.to_s
          module0 = "mod0"
          module1 = "mod1"
          File.copy(ctx.driver_path, path)

          pm.load(module_id: module0, driver_key: path)
          pm.load(module_id: module1, driver_key: path)
          pm.driver_loaded?(path).should be_true
          pm.module_loaded?(module0).should be_true
          pm.module_loaded?(module1).should be_true
          pm.unload(module0)
          pm.module_loaded?(module0).should be_false
          pm.module_loaded?(module1).should be_true
          pm.driver_loaded?(path).should be_true
        end
      end
    end
  end
end
