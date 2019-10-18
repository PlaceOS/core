require "action-controller/logger"
require "engine-drivers/helper"
require "rethinkdb-orm"

abstract class ACAEngine::Core::Resource(T)
  include ACAEngine::Drivers::Helper

  alias Error = NamedTuple(name: String, reason: String)
  getter errors : Array(Error) = [] of Error
  getter processed : Array(T) = [] of T

  private getter logger : Logger
  private getter resource_channel : Channel(T)

  abstract def process_resource(resource : T) : Bool

  def initialize(@logger = ActionController::Logger.new, buffer_size : Int32 = 64)
    @resource_channel = Channel(T).new(buffer_size)

    # Listen for changes on the resource table
    spawn watch_resources

    # Load all the resources into a channel
    initial_resource_count = load_resources

    # TODO: Defer using a form of Promise.all
    initial_resource_count.times { _process_resource(consume_resource) }

    # Begin background processing
    spawn watch_processing
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

  # Consume the resource, pop onto the processed array
  private def _process_resource(resource : T)
    processed << resource if process_resource(resource)
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
    spawn _process_resource(resource)
  end
end
