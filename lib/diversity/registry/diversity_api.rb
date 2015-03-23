# coding: utf-8
require 'addressable/uri'
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
        cache_options: {
          adapter: :Memory,
          adapter_options: {},
          transformer: {
            key: [],
            value: []
          },
          ttl: 3600
        },
        logger: nil,
        validate_spec: false
      }

      def initialize(options = {})
        @options = DEFAULT_OPTIONS.keep_merge(options)
        @logger = @options.fetch(:logger, nil)
        init_cache(@options[:cache_options])
        fail "Invalid backend URL: #{@options[:backend_url]}!" unless ping_ok
      end

      # Returns a list of installed components
      #
      # @return [Hash] A hash of component_name => [component_versions]
      def installed_components
        component_versions = {}
        components = call_api('components/')
        components.each do |component|
          version_objs = get_installed_versions(component[:name])
          version_objs.sort! { |a, b| b <=> a }
          component_versions[component[:name]] = version_objs
        end
        component_versions
      end

      def get_component(name, version = nil)
        requirement =
          (version.nil? or version == '*') ? Gem::Requirement.default :
          version.is_a?(Gem::Requirement)  ? version                  :
          Gem::Requirement.create(normalize_requirement(version))

        begin
          versions = get_installed_versions(name)
        rescue
          return nil
        end
        version_path = versions.
          select {|version_obj| requirement.satisfied_by?(version_obj) }.
          sort.last.to_s

        if version_path == ''
          # We don't fail on components we don't have, but here we have the component but not the
          # version...
          log("No match for version \"#{version}\" of #{name}.  We have #{versions.inspect}?\n")

          # Let's use the latest version we have as a failsafe.  Could get bad, but not worse than
          # no component at all.
          version_path = versions.sort.last.to_s
        end

        #puts "#{name} - selected #{version_path} for required #{version} (#{requirement} norm: #{normalize_requirement(version)}) out of #{versions.to_json}\n"

        base_url = "#{@options[:backend_url]}components/#{name}/#{version_path}/files"
        spec = safe_load("#{base_url}/diversity.json")
        #puts "Got spec from #{name}:#{version_path} on #{base_url}:\n#{spec}"

        Component.new(
          spec,
          { base_url: base_url, validate_spec: @options[:validate_spec] }
        )
      end

      def cache_contains?(url)
        @cache.key?(url)
      end

      # Purges the cache for a specific URL
      #
      # @param [String]
      # @return [Object]
      def cache_purge(url = nil)
        url ? @cache.delete(url) : @cache.clear
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
        return @cache.load(url) if @cache.key?(url)

        response = Unirest.get(url)
        fail "Error when calling API on #{url}: #{response.inspect}" unless response.code == 200
        fail 'Invalid content type' unless response.headers[:content_type] == 'application/json'
        @cache.store(url, JSON.parse(response.raw_body, symbolize_names: true))
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
      end

      # Checks whether the diversity API is live and kicking.
      #
      # @return [true|false]
      def ping_ok
        return false unless @options[:backend_url]
        # Make sure we have a real workable URL
        begin
          url = Addressable::URI.parse(@options[:backend_url])
          url.path << '/' unless url.path[-1] == '/'
          url = url.to_s
        rescue
          return false
        end
        response = Unirest.get(url)
        if response.code == 200 &&
           response.raw_body == 'Welcome to Diversity Api'
          @options[:backend_url] = url
          return true
        else
          return false
        end
      end
    end
  end
end
