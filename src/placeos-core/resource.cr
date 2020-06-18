require "deque"
require "promise"
require "rethinkdb-orm"

require "placeos-compiler/drivers"
require "placeos-compiler/drivers/helper"

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

  abstract def process_resource(event : NamedTuple(resource: T, action: Action)) : Result

  def initialize(
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
    load_resources

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
  private def load_resources : Nil
    waiting = [] of Promise::DeferredPromise(Nil)
    all(T).in_groups_of(channel_buffer_size).each do |resources|
      resources.each do |resource|
        waiting << Promise.defer { _process_event({resource: resource, action: Action::Created}) }
      end
      Promise.all(waiting).get
      waiting.clear
    end
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

      Log.debug { {message: "resource event", type: T.name, action: event[:action].to_s, id: event[:resource].id} }
      event_channel.send(event)
    end
  rescue e
    unless e.is_a?(Channel::ClosedError)
      Log.error(exception: e) { {message: "error while watching for resources"} }
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
      Log.error(exception: e) { {message: "error while consuming resource queue"} }
      watch_processing
    end
  end

  # Process the event, place into the processed buffer
  #
  private def _process_event(event : NamedTuple(resource: T, action: Action)) : Nil
    Log.context.set({
      resource_type:    T.name,
      resource_handler: self.class.name,
      resource_action:  event[:action].to_s,
    })

    Log.debug { "processing resource event" }
    begin
      case process_resource(event)
      when Result::Success
        processed.push(event)
        processed.shift if processed.size > @processed_buffer_size
        Log.info { "processed resource event" }
      when Result::Skipped then Log.info { "resource processing skipped" }
      when Result::Error   then Log.warn { {message: "resource processing failed", resource: event[:resource].to_json} }
      end
    rescue e : ProcessingError
      Log.warn { {message: "resource processing failed", error: "#{e.name} failed with #{e.message}"} }
      errors << e.to_error
    end
  rescue e
    Log.error(exception: e) { {message: "while processing resource event", resource: event[:resource].inspect} }
  end
end
