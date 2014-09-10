require 'json'

module Diversity
  # An ordinary JsonObject blessed with the ability to validate other
  # JsonObjects
  class JsonSchema < JsonObject
    def validate(data)
      # Automatically convert Diversity::JsonObjects to hashes
      data = data.data if data.is_a?(Diversity::JsonObject)
      errors = JSON::Validator.fully_validate(@data, data)
      #fail Diversity::Exception,
      #  "Configuration does not match schema. Errors:\n#{errors.join("\n")}",
      #  caller unless errors.empty?
      puts "Configuration does not match schema. Errors:\n#{errors.join("\n")}" unless errors.empty?
      true
    end
  end

end
