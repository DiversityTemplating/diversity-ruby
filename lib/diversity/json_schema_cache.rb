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
      use :Transformer, key: [:to_s], value: [:marshal]
      adapter :LRUHash, max_count: 100
    end

    # Returns the JSON schema denoted by key
    #
    # @param [String] key
    # @param [Hash] options
    # @return Diversity::JsonSchema
    def self.[](key, options = {})
      cache_key = "#{key}##{Digest::MD5.hexdigest(options.to_s)}"
      return @cache[cache_key] if @cache.key?(cache_key)
      @cache[cache_key] = load_json(key, JsonSchema, options)
      @cache[cache_key]
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
