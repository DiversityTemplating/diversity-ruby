require 'moneta'
require_relative 'json_schema'

module Diversity
  # Class used for caching schemas so that they don't need to be fetched
  # more than once
  class JsonSchemaCache
    extend Common

    # Create a new cache
    @cache = Moneta.build do
      use :Expires, expires: 3600
      adapter :LRUHash, max_count: 100
    end

    # Returns the JSON schema denoted by key
    #
    # @param [String] key
    # @return Diversity::JsonSchema
    def self.[](key)
      return @cache[key] if @cache.key?(key)
      @cache[key] = load_json(key, JsonSchema)
      @cache[key]
    end

    # Purges one (or all) items from the cache
    #
    # @param [String] key
    # @return [Object]
    def self.purge(key = nil)
      key ? @cache.delete(key) : @cache.clear
    end
  end
end
