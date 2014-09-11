require 'digest/sha1'
require 'eventmachine'
require 'fiber'
require 'json'
require 'json-rpc-client'
require 'json-schema'
require 'rake/file_list'
require 'rubygems/requirement'
require 'rubygems/version'
require_relative 'common'
require_relative 'exception'

# https://raw.githubusercontent.com/DiversityTemplating/Diversity/master/validation/diversity.schema.json

module Diversity
  # Class representing an external component
  class Component
    include Common

    Configuration =
      Struct.new(
        :name, :version, :templates, :styles, :scripts, :dependencies,
        :type, :pagetype, :context, :settings, :angular,
        :partials, :themes, :fields, :title, :thumbnail, :price, :assets,
        :src, :i18n, :base_path, :description
      )

    Configuration.members.each do |property_name|
      define_method(property_name) { @configuration[property_name] }
    end

    # Creates a new component from a configuration resource (file or URL)
    #
    # @param [String] resource configuration resource
    # @raise [Diversity::Exception] if the resource cannot be loaded
    # @return [Diversity::Component]
    def initialize(resource, skip_validation = false)
      fail Diversity::Exception,
           'Failed to load config file',
           caller unless (data = safe_load(resource))
      @configuration = Configuration.new
      if remote?(resource)
        @configuration.src = Addressable::URI.parse(resource).to_s
        @configuration.base_path = uri_base_path(@configuration.src)
      else
        @configuration.src = File.expand_path(resource)
        @configuration.base_path = File.dirname(@configuration.src)
      end
      schema = JsonSchemaCache[File.join(File.dirname(__FILE__), 'diversity.schema.json')]
      schema.validate(data) unless skip_validation
      @raw = parse_config(data)
      @checksum = Digest::SHA1.hexdigest(dump)
      populate(@raw)
    end

    # Returns a JSON dump of the component configuration
    #
    # @return [String]
    def dump
      JSON.pretty_generate(@raw)
    end

    # Resolves context in component by asking the API
    #
    # @param [URI|String] backend_url (including any query parameters representing context)
    # @param [Hash] context Context variables
    # @return [Hash]
    def resolve_context(backend_url, context = {})
      client = JsonRpcClient.new(backend_url.to_s, asynchronous_calls: false)
      resolved_context = {}
      context.each_pair do |key, settings|
        # Round 1 - Resolve context
        new_settings = settings.dup
        new_settings['params'].map! do |param|
          if param.is_a?(String) && (matches = /(\{\{(.+)\}\})/.match(param))
            # Param contains a Mustache template, try to find the value in the context
            normalized = matches[2].strip.to_sym
            fail Diversity::Exception,
                 "No such variable #{normalized}",
                 caller unless context.key?(normalized)
            param.gsub!(matches[0], context[normalized.to_sym].to_s)
          end
          param
        end
        # Round 2 - Query API
        result = nil
        EventMachine.run do
          fiber = Fiber.new do
            result = client._call_sync(new_settings['method'], new_settings['params'])
            EventMachine.stop
          end
          fiber.resume
        end
        resolved_context[key] = result
      end
      resolved_context
    end

    private

    # Parses requirement strings and creates requirements that matches the requirements
    # of the current component
    # @param [Hash] hsh
    # @return [Array]
    def get_dependencies(hsh)
      hsh.each_with_object({}) do |e, res|
        req_string = e.last.to_s
        # We need to handle both remote and local dependencies
        if remote?(req_string) # Remote dependency
          req = Addressable::URI.parse(req_string)
        else # Local dependency
          req = Gem::Requirement.new(normalize_requirement(req_string))
        end
        res[e.first.to_s] = req
      end
    end

    # Parses a component configuration file
    #
    # @param [String] data configuration data
    # @raise [Diversity::Exception] if the configuration cannot be parsed
    # @return [nil]
    def parse_config(data)
      begin
        JSON.parse(data, symbolize_names: false)
      rescue JSON::ParserError
        raise Diversity::Exception, 'Failed to parse config file', caller
      end
    end

    # Populates the object with data from different fields in the config file
    #
    # @param [Hash] hsh
    # @return [nil]
    def populate(hsh)
      @configuration.name = hsh['name']
      @configuration.version = Gem::Version.new(hsh['version'])
      @configuration.templates = Rake::FileList.new(hsh.fetch('template', []))
      @configuration.styles = Rake::FileList.new(hsh.fetch('style', []))
      @configuration.scripts = Rake::FileList.new(hsh.fetch('script', []))
      @configuration.dependencies = get_dependencies(hsh.fetch('dependencies', {}))
      @configuration.type = hsh.fetch('type', nil)
      @configuration.pagetype = hsh.fetch('pagetype', nil)
      @configuration.context = hsh.fetch('context', {})
      @configuration.settings = JsonSchema.new(hsh.fetch('settings', {}))
      @configuration.angular = hsh.fetch('angular', nil)
      @configuration.angular = @configuration.name if @configuration.angular == true # If set to true, use component name
      @configuration.partials = hsh.fetch('partials', {})
      @configuration.themes = Rake::FileList.new(hsh.fetch('themes', []))
      @configuration.fields = hsh.fetch('fields', {})
      @configuration.title = hsh.fetch('title', nil)
      @configuration.description = hsh.fetch('description', nil)
      @configuration.thumbnail = hsh.fetch('thumbnail', nil)
      @configuration.price = hsh.fetch('price', nil)
      @configuration.assets = Rake::FileList.new(hsh.fetch('assets', []))
      @configuration.i18n = hsh.fetch('i18n', {})
    end
  end
end
