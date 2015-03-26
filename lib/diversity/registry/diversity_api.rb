# coding: utf-8
require 'addressable/uri'
require 'json'
require 'unirest'
require 'null_logger'

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
          shared: false,
          ttl: 3600
        },
        logger: NullLogger.instance,
        validate_spec: false
      }

      def initialize(options = {})
        @options = DEFAULT_OPTIONS.keep_merge(options)
        @logger = @options[:logger]
        @instances = {}
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
          version_objs = get_installed_versions(component['name'])
          version_objs.sort! { |a, b| b <=> a }
          component_versions[component['name']] = version_objs
        end
        component_versions
      end

      def get_component(name, version = nil)
        # Make requirement into diversity-api path
        if version.nil?
          req = '*'
        elsif version.start_with?('^')
          # Caret version:
          # ^1.2.3 => 1
          # ^0.1.2 => 0.1
          # ^0.0.1 => 0.0.1
          rawversion = version.dup
          rawversion[0] = '' # Remove the caret
          req_parts = []
          rawversion.split('.').each do |part|
            req_parts.push(part)
            break if (part.to_i > 0)
          end

          req = req_parts.join('.')
        else
          req = version
        end

        # This call could fail.  That means we don't have what's asked for, so let it fail.
        spec = call_api('components', name, req)
        version_path = spec['version']

        instance_key = "component:#{name}:#{version_path}"
        @logger.debug do
          @instances.key?(instance_key) ?
            "Got #{@instances[instance_key]} from cache" :
            "Uncached, fetching #{name}:#{version_path} (from #{version})"
        end
        return @instances[instance_key] if @instances.key?(instance_key)

        base_url = "#{@options[:backend_url]}components/#{name}/#{version_path}/files"

        @instances[instance_key] = Component.new(
          spec,
          { base_url: base_url, validate_spec: @options[:validate_spec], logger: @logger },
          self
        )
      end

      def get_asset(component, path)
        call_api('components', component.name, component.version, 'files', path)
      end

      private

      # Calls the diversity REST Api and parses the response
      #
      # @param [Array] path
      # @return [Hash|Array|String] Parsed JSON or raw HTML
      def call_api(*path)
        url = @options[:backend_url]
        path.each do |part|
          url = File.join(url, part)
        end
        if @cache.key?(url)
          @logger.debug("Found #{url} in cache.\n")
          return @cache.load(url)
        end

        @logger.debug("#{url} not found in cache. Fetching it from backend.\n")

        response = Unirest.get(url)
        fail "Error when calling API on #{url}: #{response.inspect}" unless response.code == 200
        if response.headers[:content_type] == 'application/json'
          @cache.store(url, JSON.parse(response.raw_body, symbolize_names: false))
        else
          @cache.store(url, response.raw_body.force_encoding('UTF-8'))
        end
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
