require "json"

module PlaceOS::Core
  # Edge-specific error tracking
  record EdgeError,
    timestamp : Time,
    edge_id : String,
    error_type : ErrorType,
    message : String,
    context : Hash(String, String),
    severity : Severity do
    include JSON::Serializable

    @[JSON::Field(converter: Time::EpochConverter)]
    getter timestamp : Time

    def initialize(@edge_id, @error_type, @message, @context = {} of String => String, @severity = Severity::Error)
      @timestamp = Time.utc
    end
  end

  enum ErrorType
    Connection
    ModuleInit
    ModuleExecution
    DriverLoad
    SystemResource

    def to_json(json : JSON::Builder)
      json.string(to_s.underscore)
    end
  end

  enum Severity
    Info
    Warning
    Error
    Critical
  end

  # Module initialization tracking
  record ModuleInitError,
    module_id : String,
    driver_key : String,
    error_message : String,
    timestamp : Time,
    retry_count : Int32 do
    include JSON::Serializable

    @[JSON::Field(converter: Time::EpochConverter)]
    getter timestamp : Time

    def initialize(@module_id, @driver_key, @error_message, @retry_count = 0)
      @timestamp = Time.utc
    end
  end

  # Edge health status
  class EdgeHealth
    include JSON::Serializable

    getter edge_id : String
    getter connected : Bool

    @[JSON::Field(converter: Time::EpochConverter)]
    getter last_seen : Time

    @[JSON::Field(converter: PlaceOS::Core::TimeSpanConverter)]
    getter connection_uptime : Time::Span

    getter error_count_24h : Int32
    getter module_count : Int32
    getter failed_modules : Array(String)

    def initialize(@edge_id : String, @connected : Bool = false, @module_count : Int32 = 0, @failed_modules : Array(String) = [] of String)
      @last_seen = Time.utc
      @connection_uptime = Time::Span.zero
      @error_count_24h = 0
    end

    def initialize(@edge_id : String, @connected : Bool, @last_seen : Time, @connection_uptime : Time::Span, @error_count_24h : Int32, @module_count : Int32, @failed_modules : Array(String))
    end

    def copy_with(
      edge_id : String? = nil,
      connected : Bool? = nil,
      last_seen : Time? = nil,
      connection_uptime : Time::Span? = nil,
      error_count_24h : Int32? = nil,
      module_count : Int32? = nil,
      failed_modules : Array(String)? = nil,
    )
      EdgeHealth.new(
        edge_id || @edge_id,
        connected.nil? ? @connected : connected,
        last_seen || @last_seen,
        connection_uptime || @connection_uptime,
        error_count_24h || @error_count_24h,
        module_count || @module_count,
        failed_modules || @failed_modules
      )
    end
  end

  # Connection metrics for edges
  record ConnectionMetrics,
    edge_id : String,
    total_connections : Int32,
    failed_connections : Int32,
    average_uptime : Time::Span,
    last_connection_attempt : Time,
    last_successful_connection : Time do
    include JSON::Serializable

    @[JSON::Field(converter: Time::EpochConverter)]
    getter last_connection_attempt : Time

    @[JSON::Field(converter: Time::EpochConverter)]
    getter last_successful_connection : Time

    @[JSON::Field(converter: PlaceOS::Core::TimeSpanConverter)]
    getter average_uptime : Time::Span

    def initialize(@edge_id)
      @total_connections = 0
      @failed_connections = 0
      @average_uptime = Time::Span.zero
      @last_connection_attempt = Time.utc
      @last_successful_connection = Time.utc
    end
  end

  # Edge module status aggregation
  record EdgeModuleStatus,
    edge_id : String,
    total_modules : Int32,
    running_modules : Int32,
    failed_modules : Array(String),
    initialization_errors : Array(ModuleInitError) do
    include JSON::Serializable

    def initialize(@edge_id, @total_modules = 0, @running_modules = 0, @failed_modules = [] of String, @initialization_errors = [] of ModuleInitError)
    end
  end

  # Connection history for tracking edge connectivity
  record ConnectionHistory,
    edge_id : String,
    connection_events : Array(ConnectionEvent) do
    include JSON::Serializable

    def initialize(@edge_id, @connection_events = [] of ConnectionEvent)
    end
  end

  record ConnectionEvent,
    timestamp : Time,
    event_type : ConnectionEventType,
    duration : Time::Span?,
    error_message : String? do
    include JSON::Serializable

    @[JSON::Field(converter: Time::EpochConverter)]
    getter timestamp : Time

    @[JSON::Field(converter: PlaceOS::Core::TimeSpanConverterOptional)]
    getter duration : Time::Span?

    def initialize(@event_type, @error_message = nil, @duration = nil)
      @timestamp = Time.utc
    end
  end

  enum ConnectionEventType
    Connected
    Disconnected
    Reconnected
    Failed

    def to_json(json : JSON::Builder)
      json.string(to_s.underscore)
    end
  end

  module TimeSpanConverter
    def self.from_json(pull : JSON::PullParser) : Time::Span
      (pull.read_int).seconds
    end

    def self.to_json(value : Time::Span, json : JSON::Builder) : Nil
      json.number(value.total_seconds.to_i64)
    end
  end

  module TimeSpanConverterOptional
    def self.from_json(pull : JSON::PullParser) : Time::Span?
      value = pull.read_raw
      if value.is_a?(Int)
        (value.as(Int64)).seconds
      else
        nil
      end
    end

    def self.to_json(span : Time::Span?, json : JSON::Builder) : Nil
      if value = span
        json.number(value.total_seconds.to_i64)
      else
        json.null
      end
    end
  end
end
