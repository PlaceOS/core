require "action-controller/logger"
require "deque"
require "rethinkdb-orm"

require "engine-drivers/helper"

abstract class ACAEngine::Core::Resource(T)
  include ACAEngine::Drivers::Helper

  alias Error = NamedTuple(name: String, reason: String)
  alias Event = RethinkORM::Changefeed::Event
  alias TaggedLogger = ActionController::Logger::TaggedLogger

  # Outcome of processing a resource
  enum Result
    Success
    Error
    Skipped
  end

  # Errors generated while processing resources
  # NOTE: rw lock?
  getter errors : Array(Error) = [] of Error

  # Buffer of recently processed elements
  # NOTE: rw lock?
  getter processed : Deque(T)

  private getter resource_channel : Channel(T)

  private getter logger : ActionController::Logger::TaggedLogger

  abstract def process_resource(resource : T) : Result

  def initialize(
    @logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT)),
    @processed_buffer_size : Int32 = 64,
    channel_buffer_size : Int32 = 64
  )
    @resource_channel = Channel(T).new(channel_buffer_size)
    @processed = Deque(T).new(processed_buffer_size)
  end

  def start : self
    # Listen for changes on the resource table
    spawn(same_thread: true) { watch_resources }
    # Load all the resources into a channel
    initial_resource_count = load_resources
    # TODO: Defer using a form of Promise.all
    initial_resource_count.times { _process_resource(consume_resource) }
    # Begin background processing
    spawn(same_thread: true) { watch_processing }

    Fiber.yield

    self
  end

  private def consume_resource : T
    resource_channel.receive
  end

  # Load all resources from the database, push into a channel
  #
  private def load_resources
    count = 0
    T.all.each do |resource|
      resource_channel.send(resource)
      count += 1
    end

    count
  end

  # Listen to changes on the resource table
  #
  private def watch_resources
    T.changes.each do |change|
      resource = change[:value]

      case change[:event]
      when Event::Deleted
        # TODO: Remove the resource
      when Event::Updated
        resource_channel.send(resource.as(T))
      when Event::Created
        resource_channel.send(resource.as(T))
      end
    end
  rescue e
    logger.tag_error(message: "error while watching for resources", error: e.inspect_with_backtrace)
    watch_resources
  end

  # Consumes resources ready for processing
  #
  private def watch_processing
    loop do
      resource = consume_resource
      spawn(same_thread: true) { _process_resource(resource) }
    end
  rescue e
    logger.tag_error(message: "error while consuming resource queue", error: e.inspect_with_backtrace)
    watch_processing unless e.is_a?(Channel::ClosedError)
  end

  # Process the resource, place into the processed buffer
  #
  private def _process_resource(resource : T)
    if process_resource(resource) == Result::Success
      processed.push(resource)
      processed.shift if processed.size > @processed_buffer_size
    end
  rescue e
    logger.tag_error(message: "while processing resource", resource: resource.inspect, error: e.inspect_with_backtrace)
  end
end
