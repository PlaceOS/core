# NOTE: This code is unused here, however could be used for rest-api
###############################################################################

require "redis"

module PlaceOS::Core::Api
  # Caching
  #############################################################################

  class_getter redis : Redis { Redis.new(url: Core::REDIS_URL) }

  # Do a look up in redis for the details
  def self.cached_details?(file_name : String, repository : String, commit : String)
    redis.get(redis_key(file_name, repository, commit))
  rescue
    nil
  end

  # Set the details in redis
  def self.cache_details(
    file_name : String,
    repository : String,
    commit : String,
    details : String,
    ttl : Time::Span = 180.days
  )
    redis.set(redis_key(file_name, repository, commit), details, ex: ttl.to_i)
  end

  def self.redis_key(file_name : String, repository : String, commit : String)
    "driver-details\\#{file_name}-#{repository}-#{commit}"
  end
end
