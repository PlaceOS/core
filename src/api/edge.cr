require "./application"

require "../placeos-core/module_manager"
require "../placeos-edge/state"
require "placeos-models/edge"
require "placeos-models/module"
require "placeos-models/settings"

module PlaceOS::Core::Api
  class Edge < Application
    base "/api/core/v1/edge/"

    getter module_manager : ModuleManager { Services.module_manager }

    # websocket handling edge connections
    @[AC::Route::WebSocket("/control")]
    def edge_control(
      socket,
      @[AC::Param::Info(description: "the edge this device is handling", example: "edge-1234")]
      edge_id : String,
    ) : Nil
      module_manager.manage_edge(edge_id, socket)
    end

    @[AC::Route::GET("/:edge_id/desired_state")]
    def desired_state(
      @[AC::Param::Info(description: "the edge id we want the desired runtime state for", example: "edge-1234")]
      edge_id : String,
    ) : PlaceOS::Edge::State::Snapshot | Nil
      edge = Model::Edge.find?(edge_id)
      raise Error::NotFound.new("edge #{edge_id} not found in database") unless edge

      modules = Model::Module.on_edge(edge_id).to_a
      last_modified = edge_last_modified(edge, modules)
      return unless stale?(last_modified: last_modified)

      drivers = [] of PlaceOS::Edge::State::DesiredDriver
      desired_modules = modules.compact_map do |mod|
        driver = mod.driver || mod.driver_id.try { |id| Model::Driver.find?(id) }
        next unless driver

        repository = driver.repository || driver.repository_id.try { |id| Model::Repository.find?(id) }
        next unless repository

        driver_path = DriverStore.new.built?(driver.file_name, driver.commit, repository.branch, repository.uri)
        next unless driver_path

        driver_key = Path[driver_path].basename.to_s
        drivers << PlaceOS::Edge::State::DesiredDriver.new(driver_key)
        PlaceOS::Edge::State::DesiredModule.new(
          module_id: mod.id.as(String),
          driver_key: driver_key,
          running: mod.running,
          payload: ModuleManager.start_payload(mod)
        )
      end

      PlaceOS::Edge::State::Snapshot.new(
        edge_id: edge_id,
        version: last_modified.to_unix_ms.to_s,
        last_modified: last_modified,
        drivers: drivers.uniq! { |driver| driver.key } || drivers,
        modules: desired_modules
      )
    end

    @[AC::Route::GET("/:edge_id/drivers/:driver_key")]
    def driver_binary(
      @[AC::Param::Info(description: "the edge id we want to stream a driver for", example: "edge-1234")]
      edge_id : String,
      @[AC::Param::Info(description: "the compiled driver key", example: "drivers_place_meet_abcdef0_amd64")]
      driver_key : String,
    ) : Nil
      raise Error::NotFound.new("edge #{edge_id} not found in database") unless Model::Edge.find?(edge_id)

      path = DriverStore.new.path(driver_key)
      raise Error::NotFound.new("driver #{driver_key} not found") unless File.exists?(path)

      response.headers["Content-Type"] = "application/octet-stream"
      render binary: File.read(path)
    end

    private def edge_last_modified(edge : Model::Edge, modules : Array(Model::Module)) : Time
      timestamps = [edge.updated_at || edge.created_at || Time.utc]

      modules.each do |mod|
        timestamps << (mod.updated_at || mod.created_at || Time.utc)

        if driver = mod.driver
          timestamps << (driver.updated_at || driver.created_at || Time.utc)
          driver.settings.each do |setting|
            timestamps << (setting.updated_at || setting.created_at || Time.utc)
          end
        end

        mod.settings.each do |setting|
          timestamps << (setting.updated_at || setting.created_at || Time.utc)
        end

        if control_system = mod.control_system
          timestamps << (control_system.updated_at || control_system.created_at || Time.utc)
          control_system.settings.each do |setting|
            timestamps << (setting.updated_at || setting.created_at || Time.utc)
          end
        end
      end

      timestamps.max
    end
  end
end
