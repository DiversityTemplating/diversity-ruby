module Diversity
  # Class that represents a JSON object. It is pretty much a wrapped
  # and glorified Hash, but has some nice methods for traversing all
  # nodes in the object.
  class JsonObject
    # Sort by key length first and then by each key
    SORT_BY_KEY = lambda do |one_obj, another_obj|
      len_cmp = one_obj.first.length <=> another_obj.first.length
      return len_cmp if len_cmp.nonzero?
      one_obj.first.each_with_index do |key, index|
        key_cmp = key <=> another_obj.first[index]
        return key_cmp if key_cmp.nonzero?
      end
      0
    end

    include Enumerable

    attr_reader :data, :source

    def initialize(data, source = nil)
      fail 'First parameter must be a hash' unless data.is_a?(Hash)
      @data = data
      @source = source
    end

    def dump
      JSON.generate(@data)
    end

    def dump_pretty
      JSON.pretty_generate(@data)
    end

    def each(&block)
      if block_given?
        # Some trickery to allow us to call a private class
        # method in Diversity::JsonObject from any subclass
        data = @data
        self.class.class_eval { traverse(data, [], &block) }
      else
        to_enum(:each)
      end
    end

    def each_key(&block)
      if block_given?
        each { |node| block.call(node.first) }
      else
        to_enum(:each_key)
      end
    end

    def each_pair(&block)
      if block_given?
        each { |node| block.call(node.first, node.last) }
      else
        to_enum(:each_pair)
      end
    end

    def each_value(&block)
      if block_given?
        each { |node| block.call(node.last) }
      else
        to_enum(:each_value)
      end
    end

    def [](*args)
      args.flatten!
      node = find { |node| node.first == args }
      node ? node.last : nil
    end

    def keys
      keys = []
      each_key { |key| keys << key }
      keys
    end

    def nodes
      nodes = []
      each { |node| nodes << node }
      nodes
    end

    def values
      values = []
      each_value { |value| values << value }
      values
    end

    def self.[](data, source = nil, klass = JsonObject)
      fail 'Must be a subclass of Diversity::JsonObject' unless klass <= JsonObject
      klass.new(data, source)
    end

    def self.traverse(data, path = [], &block)
      block.call([path, data])
      data.each_pair do |key, value|
        traverse(value, (path.dup << key), &block) if value.is_a?(Hash)
      end
    end

    private_class_method :traverse

  end
end
