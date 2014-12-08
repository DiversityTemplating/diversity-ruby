# encoding: utf-8
require_relative 'json_object'

module Diversity
  # An ordinary JsonObject blessed with the ability to validate other
  # JsonObjects
  class JsonSchema < JsonObject
    DEFAULT_OPTIONS = { skip_validation: false }

    attr_reader :options

    def initialize(data, source = nil, options = {})
      super(data, source)
      @options = DEFAULT_OPTIONS.keep_merge(options)
    end

    # Validates the specified JSON data against the current object
    #
    # @param [Diversity::JsonObject|Hash|String] data
    # @return [Array]
    def validate(data)
      # Bail early if validation is turned off
      return [] if @options[:skip_validation]
      # Automatically convert Diversity::JsonObjects to hashes
      data = data.data if data.is_a?(Diversity::JsonObject)
      require 'json-schema'
      JSON::Validator.fully_validate(@data, data)
    end
  end
end
