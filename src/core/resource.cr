require "action-controller/logger"
require "deque"
require "rethinkdb-orm"

require "drivers/helper"

# Internally abstracts data event streams.
#
abstract class PlaceOS::Core::Resource(T)
  include PlaceOS::Drivers::Helper

  alias Error = NamedTuple(name: String, reason: String)
  alias Action = RethinkORM::Changefeed::Event

  class ProcessingError < Exception
    getter name

    def initialize(@name : String?, @message : String?)
      super(@message)
    end

    def to_error
      {name: name || "", reason: message || ""}
    end
  end

  # TODO: Add when crystal supports generic aliasing
  # alias Event(T) = NamedTuple(resource: T, action: Action)

  # Outcome of processing a resource
  enum Result
    Success
    Error
    Skipped
  end

  # Errors generated while processing resources
  getter errors : Array(Error) = [] of Error

  # NOTE: rw lock?
  # TODO: move away from error array, just throw the error in process resource
  #       that way it can catch the error and log it. this is currently a memory leak
  private getter channel_buffer_size
  private getter processed_buffer_size

  # Buffer of recently processed elements
  # NOTE: rw lock?
  getter processed : Deque(NamedTuple(resource: T, action: Action))
  private getter event_channel : Channel(NamedTuple(resource: T, action: Action))

  alias TaggedLogger = ActionController::Logger::TaggedLogger
  private getter logger : TaggedLogger

  abstract def process_resource(event : NamedTuple(resource: T, action: Action)) : Result

  def initialize(
    @logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT)),
    @processed_buffer_size : Int32 = 64,
    @channel_buffer_size : Int32 = 64
  )
    @event_channel = Channel(NamedTuple(resource: T, action: Action)).new(channel_buffer_size)
    @processed = Deque(NamedTuple(resource: T, action: Action)).new(processed_buffer_size)
  end

  def start : self
    processed.clear
    errors.clear
    @event_channel = Channel(NamedTuple(resource: T, action: Action)).new(channel_buffer_size) if event_channel.closed?

    # Listen for changes on the resource table
    spawn(same_thread: true) { watch_resources }
    # Load all the resources into a channel
    initial_resource_count = load_resources
    # TODO: Defer using a form of Promise.all
    initial_resource_count.times { _process_event(consume_event) }
    # Begin background processing
    spawn(same_thread: true) { watch_processing }
    Fiber.yield

    self
  end

  def stop : self
    event_channel.close
    self
  end

  private def consume_event : {resource: T, action: Action}
    event_channel.receive
  end

  # Load all resources from the database, push into a channel
  #
  private def load_resources
    count = 0
    T.all.each do |resource|
      event_channel.send({resource: resource, action: Action::Created})
      count += 1
    end

    count
  end

  # Listen to changes on the resource table
  #
  private def watch_resources
    T.changes.each do |change|
      break if event_channel.closed?
      event = {
        action:   change[:event],
        resource: change[:value],
      }

      logger.tag_debug("resource event", type: T.name, action: event[:action], id: event[:resource].id)
      event_channel.send(event)
    end
  rescue e
    unless e.is_a?(Channel::ClosedError)
      logger.tag_error("error while watching for resources", error: e.inspect_with_backtrace)
      watch_resources
    end
  end

  # Consumes resources ready for processing
  #
  private def watch_processing
    loop do
      event = consume_event
      spawn(same_thread: true) { _process_event(event) }
    end
  rescue e
    unless e.is_a?(Channel::ClosedError)
      logger.tag_error("error while consuming resource queue", error: e.inspect_with_backtrace)
      watch_processing
    end
  end

  # Process the event, place into the processed buffer
  #
  private def _process_event(event : NamedTuple(resource: T, action: Action))
    meta = {
      id:      event[:resource].id,
      type:    T.name,
      handler: self.class.name,
      action:  event[:action],
    }

    logger.tag_debug("processing resource event", **meta)
    begin
      case process_resource(event)
      when Result::Success
        processed.push(event)
        processed.shift if processed.size > @processed_buffer_size
        logger.tag_info("processed resource event", **meta)
      when Result::Skipped then logger.tag_info("processing skipped", **meta)
      end
    rescue e : ProcessingError
      logger.tag_warn("processing #{e.name} failed: #{e.message}", **meta)
      errors << e.to_error
    end
  rescue e
    logger.tag_error("while processing resource event", resource: event[:resource].inspect, error: e.inspect_with_backtrace)
  end
end
