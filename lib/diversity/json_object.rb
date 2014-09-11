module Diversity

  class JsonObject

    SORT_BY_KEY = lambda do |a, b|
      len_cmp = a.first.length <=> b.first.length
      return len_cmp if len_cmp.nonzero?
      a.first.each_with_index do |k, idx|
        key_cmp = k <=> b.first[idx]
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

    def dump(pretty = false)
      if pretty
        JSON.pretty_generate(@data)
      else
        JSON.generate(@data)
      end
    end

    def each(&block)
      fail 'Each must be called with a block' unless block_given?
      JsonObject.send(:traverse, @data, [], &block)
    end   

    def each_key(&block)
      each { |node| block.call(node.first) }
    end

    def each_pair(&block)
      each { |node| block.call(node.first, node.last) }
    end

    def each_value(&block)
      each { |node| block.call(node.last) }
    end

    def self.[](data, source = nil, klass = JsonObject)
      fail "Must be a subclass of Diversity::JsonObject" unless klass <= JsonObject
      klass.new(data, source)
    end

    def JsonObject.traverse(data, path = [], &block)
      yield [path, data] if block_given?
      data.each_pair do |k, v|
        traverse(v, (path.dup << k) , &block) if v.is_a?(Hash)
      end
    end

    private_class_method :traverse

  end

end
