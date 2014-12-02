require 'json-schema'
require_relative 'json_object'

module Diversity
  # An ordinary JsonObject blessed with the ability to validate other
  # JsonObjects
  class JsonSchema < JsonObject
    # Validates the specified JSON data against the current object
    #
    # @param [Diversity::JsonObject|Hash|String] data
    # @return [true]
    def validate(data)
      # Automatically convert Diversity::JsonObjects to hashes
      data = data.data if data.is_a?(Diversity::JsonObject)
      errors = JSON::Validator.fully_validate(@data, data)
      fail Diversity::Exception,
        "Configuration does not match schema. Errors:\n#{errors.join("\n")}",
        caller unless errors.empty?
      true
    end
  end

end
