module Diversity
  # Class that represents a JSON object. It is pretty much a wrapped
  # and glorified Hash, but has some nice methods for traversing all
  # nodes in the object.
  class JsonObject
    include Enumerable

    attr_reader :data, :source

    def initialize(data, source = nil, options = {})
      fail 'First parameter must be a hash' unless data.is_a?(Hash)
      @data = data
      @source = source
      @options = options
    end

    # Returns the current object as a JSON string
    #
    # @return [String]
    def dump
      JSON.generate(@data)
    end

    # Returns the current object as a prettified JSON string
    #
    # @return [String]
    def dump_pretty
      JSON.pretty_generate(@data)
    end

    # Iterates over all nodes in the current object
    #
    # @return [nil|Enumerator]
    def each(&block)
      if block_given?
        # Some trickery to allow us to call a private class
        # method in Diversity::JsonObject from any subclass
        data = @data
        self.class.class_eval { traverse(data, [], &block) }
        nil
      else
        to_enum(:each)
      end
    end

    # Iterates over all keys in the current object
    #
    # @return [nil|Enumerator]
    def each_key(&block)
      if block_given?
        each { |node| block.call(node.first) }
      else
        to_enum(:each_key)
      end
    end

    # Iterates over all nodes in the current object
    #
    # @return [nil|Enumerator]
    def each_pair(&block)
      if block_given?
        each { |node| block.call(node.first, node.last) }
      else
        to_enum(:each_pair)
      end
    end

    # Iterates over all values in the current object
    #
    # @return [nil|Enumerator]
    def each_value(&block)
      if block_given?
        each { |node| block.call(node.last) }
      else
        to_enum(:each_value)
      end
    end

    # Returns a node by key
    #
    # @param [Object] args
    # @return [Array|nil]
    def [](*args)
      args.flatten!
      found_node = find { |node| node.first == args }
      found_node ? found_node.last : nil
    end

    # Returns an array of keys in the object
    #
    # @return [Array]
    def keys
      keys = []
      each_key { |key| keys << key }
      keys
    end

    # Returns an array of nodes in the object
    #
    # @return [Array]
    def nodes
      nodes = []
      each { |node| nodes << node }
      nodes
    end

    # Returns an array of values in the object
    #
    # @return [Array]
    def values
      values = []
      each_value { |value| values << value }
      values
    end

    # Returns an instance of JsonObject (or a subclass thereof)
    #
    # @param [Hash] data
    # @param [String] source
    # @param [Class] klass
    # @param [Hash] options
    def self.[](data, source = nil, klass = JsonObject, options = {})
      fail 'Must be a subclass of Diversity::JsonObject' unless klass <= JsonObject
      klass.new(data, source, options)
    end

    def self.traverse(data, path = [], &block)
      block.call([path, data])
      if data.is_a?(Array)
        data.each_with_index do |value, idx|
          traverse(value, (path.dup << idx), &block) if
            value.is_a?(Array) || value.is_a?(Hash)
        end
      elsif data.is_a?(Hash)
        data.each_pair do |key, value|
          traverse(value, (path.dup << key), &block) if
            value.is_a?(Array) || value.is_a?(Hash)
        end
      end
    end

    private_class_method :traverse
  end
end
