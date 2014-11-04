require 'cache'
require 'json'
require 'unirest'

module Diversity
  module Registry
    # Class representing a registry connected to an instance
    # of diversity-api. See
    # https://github.com/DiversityTemplating/diversity-api
    # for further information
    class DiversityApi < Base

      # Default options
      DEFAULT_OPTIONS = {
        backend_url: nil,
        cache_options: { expiration: 3600, max_num: 100 },
        skip_validation: false
      }

      def initialize(options = {})
        @options = DEFAULT_OPTIONS.merge(options)
        @cache = Cache.new(@options[:cache_options])
        fail 'Invalid backend URL!' unless ping_ok
      end

      # Returns a list of installed components
      #
      # @return [Array] An array of Component objects
      def installed_components
        component_objs = []
        components = call_api('components/')
        components.each do |component|
          version_objs = get_installed_versions(component[:name])
          version_objs.each do |version_obj|
            begin
              base_url = "#{@options[:backend_url]}components/#{component[:name]}" +
                "/#{version_obj.to_s}/files"
              spec = safe_load("#{base_url}/diversity.json")
              puts "Got spec from #{component[:name]}:#{version_obj} on #{base_url}:\n#{spec}"

              component_objs <<
                Component.new(
                  self,
                  spec,
                  { base_url: base_url, skip_validation: @options[:skip_validation] }
                )
            rescue Exception => err
              next # Silently ignore non-working components
            end
          end
        end
        component_objs
      end

      def get_component(name, version = nil)
        cache_key = "component:#{name}:#{version}"
        return @cache[cache_key] if @cache.has_key?(cache_key)

        requirement =
          (version.nil? or version == '*') ? Gem::Requirement.default :
          version.is_a?(Gem::Requirement)  ? version                  :
          Gem::Requirement.create(version)

        begin
          versions = get_installed_versions(name)
        rescue
          # If the component isn't available by diversity api, let someone else try.
          return super
        end
        version_path = versions.
          select {|version_obj| requirement.satisfied_by?(version_obj) }.
          sort.last.to_s

        base_url = "#{@options[:backend_url]}components/#{name}/#{version_path}/files"
        spec = safe_load("#{base_url}/diversity.json")
        puts "Got spec from #{name}:#{version_path} on #{base_url}:\n#{spec}"

        @cache[cache_key] =
          Component.new(
            self, spec,
            { base_url: base_url, skip_validation: @options[:skip_validation] }
          )
      end

      def cache_contains?(url)
        @cache.cached?(url)
      end

      # Purges the cache for a specific URL
      #
      # @param [String]
      # @return [Object]
      def cache_purge(url = nil)
        url ? @cache.invalidate(url) : @cache.invalidate_all
      end

      # Return statistics about cached objects
      def cache_stats
        cache_size, num_items, num_hits, num_misses  = @cache.statistics
        {
          cache_size: cache_size,
          num_items: num_items,
          num_hits: num_hits,
          num_misses: num_misses
        }
      end

      private

      # Calls the diversity REST Api and parses the response
      #
      # @param [Array] path
      # @return Hash
      def call_api(*path)
        url = @options[:backend_url]
        path.each do |part|
          url = File.join(url, part)
        end
        return @cache[url] if @cache.cached?(url)
        response = Unirest.get(url)
        fail "Error when calling API on #{url}: #{response.inspect}" unless response.code == 200
        fail 'Invalid content type' unless response.headers[:content_type] == 'application/json'
        @cache[url] = JSON.parse(response.raw_body, symbolize_names: true)
        @cache[url]
      end

      # Returns a list of available versions for a specific component
      #
      # @param [String] component_name
      # @return [Array]
      def get_installed_versions(component_name)
        version_objs = []
        versions = call_api('components', component_name)
        versions.each do |version|
          begin
            version_objs << Gem::Version.new(version)
          rescue ArgumentError
            next # Ignore malformed version numbers
          end
        end
        version_objs.sort
        # TODO: Talk to David about default versions
        # version_objs << Gem::Version.new('0.0.1') if version_objs.empty?
        version_objs
      end

      # Checks whether the diversity API is live and kicking.
      #
      # @return [true|false]
      def ping_ok
        return false unless @options[:backend_url]
        response = Unirest.get(@options[:backend_url])
        response.code == 200 &&
          response.raw_body == 'Welcome to Diversity Api'
      end
    end
  end
end
