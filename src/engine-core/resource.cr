require "action-controller/logger"
require "deque"
require "rethinkdb-orm"

require "engine-drivers/helper"

abstract class ACAEngine::Core::Resource(T)
  include ACAEngine::Drivers::Helper

  alias Error = NamedTuple(name: String, reason: String)

  # Errors generated while processing resources
  # NOTE: rw lock?
  getter errors : Array(Error) = [] of Error

  # Buffer of recently processed elements
  # NOTE: rw lock?
  getter processed : Deque(T)

  private getter resource_channel : Channel(T)

  private getter logger : Logger

  abstract def process_resource(resource : T) : Bool

  def initialize(
    @logger = ActionController::Logger.new,
    @processed_buffer_size : Int32 = 64,
    channel_buffer_size : Int32 = 64
  )
    @resource_channel = Channel(T).new(channel_buffer_size)
    @processed = Deque(T).new(processed_buffer_size)

    # Listen for changes on the resource table
    spawn(same_thread: true) { watch_resources }

    # Load all the resources into a channel
    initial_resource_count = load_resources

    # TODO: Defer using a form of Promise.all
    initial_resource_count.times { _process_resource(consume_resource) }

    # Begin background processing
    spawn(same_thread: true) { watch_processing }
  end

  def consume_resource : T
    resource_channel.receive
  end

  # Load all resources from the database, push into a channel
  def load_resources
    count = 0
    T.all.each do |resource|
      resource_channel.send(resource)
      count += 1
    end

    count
  end

  # Consume the resource, pop onto the processed buffer
  private def _process_resource(resource : T)
    if process_resource(resource)
      processed.push(resource)
      processed.shift if processed.size > @processed_buffer_size
    end
  end

  # Listen to changes on the resource table
  def watch_resources
    T.changes.each do |change|
      resource = change[:value]

      case change[:event]
      when RethinkORM::Changefeed::Event::Deleted
        # TODO: Remove the resource
      when RethinkORM::Changefeed::Event::Updated
        resource_channel.send(resource.as(T))
      when RethinkORM::Changefeed::Event::Created
        resource_channel.send(resource.as(T))
      end
    end
  end

  def watch_processing
    # Block on the resource channel
    resource = consume_resource
    spawn(same_thread: true) { _process_resource(resource) }
  end
end
