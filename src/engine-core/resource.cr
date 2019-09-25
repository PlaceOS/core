require "logger"

abstract class Engine::Core::Resource(T)
  private getter logger : Logger
  private getter resource_channel = Channel(T).new

  def initialize(@logger = Logger.new(STDOUT))
    # Listen for changes on the resource table
    spawn watch_resources

    # Load all the resources into a channel
    load_resource

    # Consume and process resources until channel drained
    while (resource = consume_resource)
      process_resource(resource)
    end

    # Begin background processing
    spawn watch_processing
  end

  def consume_resource : T?
    resource_channel.receive?
  end

  # Load all resources from the database, push into a queue
  def load_resources
    T.all.each do |resource|
      resource_channel.send(resource)
    end
  end

  abstract def process_resource(resource : T)

  # Listen to changes on the resource table
  def watch_resources
    T.changes do |change|
      resource = change[:value]

      case change[:event]
      when RethinkORM::Changefeed::Deleted
        # TODO: Remove the resource
      when RethinkORM::Changefeed::Updated
        resource_channel.send(resource)
      when RethinkORM::Changefeed::Created
        resource_channel.send(resource)
      end
    end
  end

  def watch_processing
    # Block on the resource channel
    resource = resource_channel.receive?
    process_resource(resource)
  end
end
