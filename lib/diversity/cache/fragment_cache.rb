require 'logger'
require 'moneta'
require 'tmpdir'

module Diversity
  module Cache
    class FragmentCache
      def initialize(data_dir = Dir.mktmpdir, logger = ::Logger.new($stdout))
        @logger = logger
        log("#{data_dir}\n")
        @cache = Moneta.new(:HashFile, dir: data_dir, expires: true, logger: true)
      end

      def key?(key, options = {})
        @cache.key?(key, options)
      end

      def load(key, options = {})
        @cache.load(key, options)
      end

      def store(key, value, options = {})
        @cache.store(key, value, options)
      end

      def delete(key, options = {})
        @cache.delete(key, options)
      end

      def clear(options = {})
        @cache.clear(options)
      end

      def log(msg)
        @logger << msg if @logger
      end

    end
  end
end
