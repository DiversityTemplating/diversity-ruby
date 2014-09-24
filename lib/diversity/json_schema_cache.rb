require 'cache'
require_relative 'json_schema'

module Diversity
  # Class used for caching schemas so that they don't need to be fetched
  # more than once
  class JsonSchemaCache
    extend Common

    # Create a new cache
    # Max number of cached items: 100
    # Expiration time: 3600 seconds (1 hour)
    @cache = Cache.new({expiration: 3600, max_num: 100})

    # Returns the JSON schema denoted by key
    #
    # @param [String] key
    # @return Diversity::JsonSchema
    def self.[](key)
      return @cache[key] if @cache.cached?(key)
      @cache[key] = load_json(key, JsonSchema)
      @cache[key]
    end

    # Purges one (or all) items from the cache
    #
    # @param [String] key
    # @return [Object]
    def self.purge(key = nil)
      key ? @cache.invalidate(key) : @cache.invalidate_all
    end
  end
end
