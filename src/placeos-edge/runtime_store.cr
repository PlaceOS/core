require "file_utils"
require "uuid"

require "./state"
require "./constants"
require "../placeos-core/driver_manager/driver_store"

module PlaceOS::Edge
  class RuntimeStore
    Log = ::Log.for(self)

    # Use the same path as driver binaries to ensure writability
    # If drivers can be stored here, state can too
    DEFAULT_PATH = Core::DriverStore::BINARY_PATH

    # Write debouncing: batch writes to reduce I/O
    WRITE_DEBOUNCE_INTERVAL = 1.second

    getter path : String

    private getter lock = Mutex.new
    private getter write_pending = Atomic(Bool).new(false)
    private getter last_core_write = Atomic(Int64).new(0_i64)

    @state : State::PersistedState

    def initialize(@path : String = DEFAULT_PATH)
      Dir.mkdir_p(File.join(path, "edge-state"))
      @state = load_state
    end

    def snapshot : State::Snapshot?
      lock.synchronize { @state.snapshot }
    end

    def last_snapshot_version : String?
      lock.synchronize { @state.last_snapshot_version }
    end

    def runtime_modules
      lock.synchronize { @state.runtime_modules.dup }
    end

    def pending_updates
      lock.synchronize { @state.pending_updates.dup }
    end

    def pending_events
      lock.synchronize { @state.pending_events.dup }
    end

    def pending_update_count : Int32
      lock.synchronize { @state.pending_updates.size.to_i32 }
    end

    def pending_event_count : Int32
      lock.synchronize { @state.pending_events.size.to_i32 }
    end

    def last_error : String?
      lock.synchronize { @state.last_error }
    end

    def save_snapshot(snapshot : State::Snapshot)
      lock.synchronize do
        @state = State::PersistedState.new(
          snapshot: snapshot,
          runtime_modules: @state.runtime_modules,
          pending_updates: @state.pending_updates,
          pending_events: @state.pending_events,
          last_error: @state.last_error,
          last_snapshot_version: snapshot.version
        )

        # Debounced write for core state
        schedule_core_write
      end
    end

    def save_runtime_module(module_id : String, runtime : State::RuntimeModule)
      lock.synchronize do
        runtime_modules = @state.runtime_modules.dup
        runtime_modules[module_id] = runtime

        @state = State::PersistedState.new(
          snapshot: @state.snapshot,
          runtime_modules: runtime_modules,
          pending_updates: @state.pending_updates,
          pending_events: @state.pending_events,
          last_error: @state.last_error,
          last_snapshot_version: @state.last_snapshot_version
        )

        # Debounced write for core state
        schedule_core_write
      end
    end

    def delete_runtime_module(module_id : String)
      lock.synchronize do
        runtime_modules = @state.runtime_modules.dup
        runtime_modules.delete(module_id)

        @state = State::PersistedState.new(
          snapshot: @state.snapshot,
          runtime_modules: runtime_modules,
          pending_updates: @state.pending_updates,
          pending_events: @state.pending_events,
          last_error: @state.last_error,
          last_snapshot_version: @state.last_snapshot_version
        )

        # Debounced write for core state
        schedule_core_write
      end
    end

    # Force immediate write of all state (for testing/shutdown)
    def flush
      lock.synchronize do
        persist_core_state
        persist_pending_updates
        persist_pending_events
      end
    end

    def queue_update(action : Protocol::RedisAction, hash_id : String, key_name : String, status_value : String?) : State::PendingRedisUpdate
      update = State::PendingRedisUpdate.new(UUID.random.to_s, action, hash_id, key_name, status_value)

      lock.synchronize do
        pending_updates = collapse_updates(@state.pending_updates.dup, update)

        # Apply backpressure: drop oldest updates if exceeding limit
        if pending_updates.size > Edge::MAX_PENDING_UPDATES
          Log.warn { "pending updates exceeded #{Edge::MAX_PENDING_UPDATES}, dropping oldest entries" }
          pending_updates = pending_updates.last(Edge::MAX_PENDING_UPDATES)
        end

        @state = State::PersistedState.new(
          snapshot: @state.snapshot,
          runtime_modules: @state.runtime_modules,
          pending_updates: pending_updates,
          pending_events: @state.pending_events,
          last_error: @state.last_error,
          last_snapshot_version: @state.last_snapshot_version
        )

        # Append to pending updates log (fast, no rewrite)
        append_pending_update(update)
      end

      update
    end

    def queue_event(event : State::RuntimeEvent) : State::PendingRuntimeEvent
      pending = State::PendingRuntimeEvent.new(UUID.random.to_s, event)

      lock.synchronize do
        pending_events = collapse_events(@state.pending_events.dup, pending)

        # Apply backpressure: drop oldest events if exceeding limit
        if pending_events.size > Edge::MAX_PENDING_EVENTS
          Log.warn { "pending events exceeded #{Edge::MAX_PENDING_EVENTS}, dropping oldest entries" }
          pending_events = pending_events.last(Edge::MAX_PENDING_EVENTS)
        end

        @state = State::PersistedState.new(
          snapshot: @state.snapshot,
          runtime_modules: @state.runtime_modules,
          pending_updates: @state.pending_updates,
          pending_events: pending_events,
          last_error: @state.last_error,
          last_snapshot_version: @state.last_snapshot_version
        )

        # Append to pending events log (fast, no rewrite)
        append_pending_event(pending)
      end

      pending
    end

    def acknowledge_update(update_id : String)
      lock.synchronize do
        @state = State::PersistedState.new(
          snapshot: @state.snapshot,
          runtime_modules: @state.runtime_modules,
          pending_updates: @state.pending_updates.reject { |update| update.id == update_id },
          pending_events: @state.pending_events,
          last_error: @state.last_error,
          last_snapshot_version: @state.last_snapshot_version
        )

        # Rewrite pending updates file (compaction)
        schedule_pending_compaction
      end
    end

    def acknowledge_event(event_id : String)
      lock.synchronize do
        @state = State::PersistedState.new(
          snapshot: @state.snapshot,
          runtime_modules: @state.runtime_modules,
          pending_updates: @state.pending_updates,
          pending_events: @state.pending_events.reject { |event| event.id == event_id },
          last_error: @state.last_error,
          last_snapshot_version: @state.last_snapshot_version
        )

        # Rewrite pending events file (compaction)
        schedule_pending_compaction
      end
    end

    def set_last_error(error : String?)
      lock.synchronize do
        @state = State::PersistedState.new(
          snapshot: @state.snapshot,
          runtime_modules: @state.runtime_modules,
          pending_updates: @state.pending_updates,
          pending_events: @state.pending_events,
          last_error: error,
          last_snapshot_version: @state.last_snapshot_version
        )

        # Debounced write for core state
        schedule_core_write
      end
    end

    # Debounced write for core state changes (snapshot, modules, error)
    private def schedule_core_write
      return if write_pending.get

      now = Time.utc.to_unix_ms
      last = last_core_write.get

      if now - last > WRITE_DEBOUNCE_INTERVAL.total_milliseconds
        # Write immediately if enough time has passed
        persist_core_state
        last_core_write.set(now)
      else
        # Schedule delayed write
        write_pending.set(true)
        spawn do
          sleep WRITE_DEBOUNCE_INTERVAL
          lock.synchronize do
            persist_core_state
            last_core_write.set(Time.utc.to_unix_ms)
            write_pending.set(false)
          end
        end
      end
    end

    # Schedule compaction of pending files (debounced)
    private def schedule_pending_compaction
      spawn do
        sleep 5.seconds # Batch acknowledgments
        lock.synchronize do
          persist_pending_updates
          persist_pending_events
        end
      end
    end

    private def collapse_updates(updates : Array(State::PendingRedisUpdate), new_update : State::PendingRedisUpdate)
      if new_update.action.hset? || new_update.action.set?
        updates.reject! do |existing|
          existing.action == new_update.action &&
            existing.hash_id == new_update.hash_id &&
            existing.key_name == new_update.key_name
        end
      end

      updates << new_update
      updates
    end

    private def collapse_events(events : Array(State::PendingRuntimeEvent), pending : State::PendingRuntimeEvent)
      event = pending.event

      if event.kind.sync_status? || event.kind.snapshot_applied?
        events.reject! do |existing|
          existing.event.kind == event.kind
        end
      end

      events << pending
      events
    end

    private def load_state : State::PersistedState
      # Load core state
      core_state = if File.exists?(core_state_file)
                     begin
                       State::PersistedState.from_json(File.read(core_state_file))
                     rescue error
                       Log.warn(exception: error) { "failed to load core state" }
                       State::PersistedState.new
                     end
                   else
                     State::PersistedState.new
                   end

      # Load pending updates from append-only log
      pending_updates = load_pending_updates

      # Load pending events from append-only log
      pending_events = load_pending_events

      # Merge into single state
      State::PersistedState.new(
        snapshot: core_state.snapshot,
        runtime_modules: core_state.runtime_modules,
        pending_updates: pending_updates,
        pending_events: pending_events,
        last_error: core_state.last_error,
        last_snapshot_version: core_state.last_snapshot_version
      )
    end

    private def load_pending_updates : Array(State::PendingRedisUpdate)
      return [] of State::PendingRedisUpdate unless File.exists?(pending_updates_file)

      updates = [] of State::PendingRedisUpdate
      File.each_line(pending_updates_file) do |line|
        next if line.strip.empty?
        updates << State::PendingRedisUpdate.from_json(line)
      rescue error
        Log.warn(exception: error) { "failed to parse pending update line" }
      end
      updates
    rescue error
      Log.warn(exception: error) { "failed to load pending updates" }
      [] of State::PendingRedisUpdate
    end

    private def load_pending_events : Array(State::PendingRuntimeEvent)
      return [] of State::PendingRuntimeEvent unless File.exists?(pending_events_file)

      events = [] of State::PendingRuntimeEvent
      File.each_line(pending_events_file) do |line|
        next if line.strip.empty?
        events << State::PendingRuntimeEvent.from_json(line)
      rescue error
        Log.warn(exception: error) { "failed to parse pending event line" }
      end
      events
    rescue error
      Log.warn(exception: error) { "failed to load pending events" }
      [] of State::PendingRuntimeEvent
    end

    # Persist core state (snapshot, modules, error) - debounced
    private def persist_core_state
      temp = "#{core_state_file}.tmp"

      begin
        # Only persist core state, not pending items
        core_only = State::PersistedState.new(
          snapshot: @state.snapshot,
          runtime_modules: @state.runtime_modules,
          pending_updates: [] of State::PendingRedisUpdate,
          pending_events: [] of State::PendingRuntimeEvent,
          last_error: @state.last_error,
          last_snapshot_version: @state.last_snapshot_version
        )

        File.write(temp, core_only.to_json)
        File.rename(temp, core_state_file)
      rescue ex : File::Error
        Log.warn(exception: ex) { "failed to persist core state, continuing in-memory only" }
        File.delete(temp) rescue nil
      end
    end

    # Append single update to log (fast, no rewrite)
    private def append_pending_update(update : State::PendingRedisUpdate)
      begin
        File.open(pending_updates_file, "a") do |file|
          file.puts(update.to_json)
        end
      rescue ex : File::Error
        Log.warn(exception: ex) { "failed to append pending update" }
      end
    end

    # Append single event to log (fast, no rewrite)
    private def append_pending_event(event : State::PendingRuntimeEvent)
      begin
        File.open(pending_events_file, "a") do |file|
          file.puts(event.to_json)
        end
      rescue ex : File::Error
        Log.warn(exception: ex) { "failed to append pending event" }
      end
    end

    # Rewrite pending updates file (compaction after acknowledgments)
    private def persist_pending_updates
      temp = "#{pending_updates_file}.tmp"

      begin
        File.open(temp, "w") do |file|
          @state.pending_updates.each do |update|
            file.puts(update.to_json)
          end
        end
        File.rename(temp, pending_updates_file)
      rescue ex : File::Error
        Log.warn(exception: ex) { "failed to compact pending updates" }
        File.delete(temp) rescue nil
      end
    end

    # Rewrite pending events file (compaction after acknowledgments)
    private def persist_pending_events
      temp = "#{pending_events_file}.tmp"

      begin
        File.open(temp, "w") do |file|
          @state.pending_events.each do |event|
            file.puts(event.to_json)
          end
        end
        File.rename(temp, pending_events_file)
      rescue ex : File::Error
        Log.warn(exception: ex) { "failed to compact pending events" }
        File.delete(temp) rescue nil
      end
    end

    private def core_state_file
      File.join(path, "edge-state", "core.json")
    end

    private def pending_updates_file
      File.join(path, "edge-state", "pending-updates.jsonl")
    end

    private def pending_events_file
      File.join(path, "edge-state", "pending-events.jsonl")
    end
  end
end
