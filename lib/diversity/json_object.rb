module Diversity

  class JsonObject

    attr_reader :data, :source

    def initialize(data, source = nil)
      fail 'First parameter must be a hash' unless data.is_a?(Hash)
      @data = data
      @source = source
    end

    def dump(pretty = false)
      if pretty
        JSON.pretty_generate(@data)
      else
        JSON.generate(@data)
      end
    end

    def self.[](data, source = nil, klass = JsonObject)
      fail "Must be a subclass of Diversity::JsonObject" unless klass <= JsonObject
      klass.new(data, source)
    end

  end

end
