require "json"

module PlaceOS::Edge
  module State
    enum RuntimeEventKind
      ModuleLoaded
      ModuleStarted
      ModuleStopped
      ModuleUnloaded
      ModuleFailed
      DriverReady
      DriverRemoved
      SnapshotApplied
      SyncStatus
    end

    struct DesiredDriver
      include JSON::Serializable

      getter key : String

      def initialize(@key : String)
      end
    end

    struct DesiredModule
      include JSON::Serializable

      getter module_id : String
      getter driver_key : String
      getter running : Bool
      getter payload : String

      def initialize(@module_id : String, @driver_key : String, @running : Bool, @payload : String)
      end
    end

    struct Snapshot
      include JSON::Serializable

      @[JSON::Field(converter: Time::EpochConverter)]
      getter last_modified : Time
      getter edge_id : String
      getter version : String
      getter drivers : Array(DesiredDriver)
      getter modules : Array(DesiredModule)

      def initialize(@edge_id : String, @version : String, @last_modified : Time, @drivers : Array(DesiredDriver), @modules : Array(DesiredModule))
      end
    end

    struct RuntimeModule
      include JSON::Serializable

      getter driver_key : String
      property loaded : Bool
      property running : Bool
      property payload : String?

      def initialize(@driver_key : String, @loaded : Bool = false, @running : Bool = false, @payload : String? = nil)
      end
    end

    struct PendingRedisUpdate
      include JSON::Serializable

      getter id : String
      getter action : Protocol::RedisAction
      getter hash_id : String
      getter key_name : String
      getter status_value : String?

      def initialize(@id : String, @action : Protocol::RedisAction, @hash_id : String, @key_name : String, @status_value : String?)
      end
    end

    struct PendingRuntimeEvent
      include JSON::Serializable

      getter id : String
      getter event : RuntimeEvent

      def initialize(@id : String, @event : RuntimeEvent)
      end
    end

    struct RuntimeEvent
      include JSON::Serializable

      @[JSON::Field(converter: Time::EpochConverter)]
      getter timestamp : Time
      getter kind : RuntimeEventKind
      getter module_id : String?
      getter driver_key : String?
      getter message : String?
      getter snapshot_version : String?
      getter backlog_depth : Int32?

      def initialize(
        @kind : RuntimeEventKind,
        @timestamp : Time = Time.utc,
        @module_id : String? = nil,
        @driver_key : String? = nil,
        @message : String? = nil,
        @snapshot_version : String? = nil,
        @backlog_depth : Int32? = nil,
      )
      end
    end

    struct PersistedState
      include JSON::Serializable

      getter snapshot : Snapshot?
      getter runtime_modules : Hash(String, RuntimeModule)
      getter pending_updates : Array(PendingRedisUpdate)
      getter pending_events : Array(PendingRuntimeEvent)
      getter last_error : String?
      getter last_snapshot_version : String?

      def initialize(
        @snapshot : Snapshot? = nil,
        @runtime_modules : Hash(String, RuntimeModule) = {} of String => RuntimeModule,
        @pending_updates : Array(PendingRedisUpdate) = [] of PendingRedisUpdate,
        @pending_events : Array(PendingRuntimeEvent) = [] of PendingRuntimeEvent,
        @last_error : String? = nil,
        @last_snapshot_version : String? = nil,
      )
      end
    end
  end
end
