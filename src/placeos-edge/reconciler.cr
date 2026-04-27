require "./state"
require "./runtime_store"
require "./binary_manager"
require "./runtime_manager"

module PlaceOS::Edge
  class Reconciler
    Log = ::Log.for(self)

    private getter runtime_store : RuntimeStore
    private getter binary_manager : BinaryManager
    private getter runtime_manager : RuntimeManager
    private getter on_event : (State::RuntimeEvent ->)?

    def initialize(
      @runtime_store : RuntimeStore,
      @binary_manager : BinaryManager,
      @runtime_manager : RuntimeManager,
      @on_event : (State::RuntimeEvent ->)? = nil,
    )
    end

    def apply(snapshot : State::Snapshot)
      desired_modules = snapshot.modules.index_by(&.module_id)
      current_modules = runtime_store.runtime_modules

      desired_driver_keys = snapshot.drivers.map(&.key).to_set
      snapshot.modules.each do |mod|
        desired_driver_keys << mod.driver_key
      end

      failed_drivers = [] of String
      failed_modules = [] of String

      # Download drivers with individual error handling for partial success
      desired_driver_keys.each do |driver_key|
        begin
          binary_manager.ensure_binary(driver_key)
          emit(State::RuntimeEvent.new(:driver_ready, driver_key: driver_key))
        rescue error
          failed_drivers << driver_key
          Log.error(exception: error) { "failed to download driver #{driver_key}" }
          emit(State::RuntimeEvent.new(:module_failed, driver_key: driver_key, message: "driver download failed: #{error.message}"))
        end
      end

      # Unload modules that are no longer desired
      current_modules.each_key do |module_id|
        next if desired_modules.has_key?(module_id)
        begin
          unload_module(module_id, current_modules[module_id])
        rescue error
          Log.error(exception: error) { "failed to unload module #{module_id}" }
        end
      end

      # Reconcile modules individually, skipping those with failed drivers
      snapshot.modules.each do |desired|
        if failed_drivers.includes?(desired.driver_key)
          failed_modules << desired.module_id
          Log.warn { "skipping module #{desired.module_id} due to failed driver #{desired.driver_key}" }
          next
        end

        begin
          reconcile_module(desired, current_modules[desired.module_id]?)
        rescue error
          failed_modules << desired.module_id
          Log.error(exception: error) { "failed to reconcile module #{desired.module_id}" }
        end
      end

      # Clean up unused drivers
      (binary_manager.compiled_drivers - desired_driver_keys).each do |driver_key|
        next if runtime_manager.driver_loaded?(driver_key)
        begin
          binary_manager.delete_binary(driver_key)
          emit(State::RuntimeEvent.new(:driver_removed, driver_key: driver_key))
        rescue error
          Log.error(exception: error) { "failed to delete driver binary #{driver_key}" }
        end
      end

      # Always save snapshot even with partial failures
      runtime_store.save_snapshot(snapshot)

      # Report overall reconciliation status
      if failed_drivers.any? || failed_modules.any?
        error_msg = "Partial reconciliation: #{failed_drivers.size} driver(s) failed, #{failed_modules.size} module(s) failed"
        runtime_store.set_last_error(error_msg)
        emit(State::RuntimeEvent.new(:snapshot_applied, snapshot_version: snapshot.version, backlog_depth: runtime_store.pending_update_count, message: error_msg))
      else
        runtime_store.set_last_error(nil)
        emit(State::RuntimeEvent.new(:snapshot_applied, snapshot_version: snapshot.version, backlog_depth: runtime_store.pending_update_count))
      end
    end

    private def reconcile_module(desired : State::DesiredModule, current : State::RuntimeModule?)
      runtime_manager.load(desired.module_id, desired.driver_key)

      runtime = current || State::RuntimeModule.new(desired.driver_key)
      runtime.loaded = true
      emit(State::RuntimeEvent.new(:module_loaded, module_id: desired.module_id, driver_key: desired.driver_key))

      if desired.running
        payload_changed = runtime.payload != desired.payload
        if runtime.running && payload_changed
          runtime_manager.stop(desired.module_id)
          emit(State::RuntimeEvent.new(:module_stopped, module_id: desired.module_id, driver_key: desired.driver_key, message: "payload changed"))
          runtime.running = false
        end

        unless runtime.running
          runtime_manager.start(desired.module_id, desired.payload)
          runtime.running = true
          emit(State::RuntimeEvent.new(:module_started, module_id: desired.module_id, driver_key: desired.driver_key))
        end
      elsif runtime.running
        runtime_manager.stop(desired.module_id)
        runtime.running = false
        emit(State::RuntimeEvent.new(:module_stopped, module_id: desired.module_id, driver_key: desired.driver_key))
      end

      runtime.payload = desired.payload
      runtime_store.save_runtime_module(desired.module_id, runtime)
    rescue error
      emit(State::RuntimeEvent.new(:module_failed, module_id: desired.module_id, driver_key: desired.driver_key, message: error.message))
      raise error
    end

    private def unload_module(module_id : String, runtime : State::RuntimeModule)
      runtime_manager.stop(module_id) if runtime.running
      runtime_manager.unload(module_id) if runtime.loaded
      runtime_store.delete_runtime_module(module_id)
      emit(State::RuntimeEvent.new(:module_unloaded, module_id: module_id, driver_key: runtime.driver_key))
    rescue error
      emit(State::RuntimeEvent.new(:module_failed, module_id: module_id, driver_key: runtime.driver_key, message: error.message))
      raise error
    end

    private def emit(event : State::RuntimeEvent)
      on_event.try &.call(event)
    end
  end
end
