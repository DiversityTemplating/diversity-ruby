require 'cache'
require_relative 'json_schema'

module Diversity
  # Class used for caching schemas so that they don't need to be fetched
  # more than once
  class JsonSchemaCache
    extend Common
    @cache = Cache.new

    # Returns the JSON schema denoted by key
    #
    # @param [String] key
    # @return Diversity::JsonSchema
    def self.[](key)
      return @cache[key] if @cache.cached?(key)
      @cache[key] = load_json(key, JsonSchema)
      @cache[key]
    end
  end
end
