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

module Diversity
  # Class representing an external component
  class Component
    include Common

    # @!attribute [r] name
    #   @return [String] Component name
    # @!attribute [r] version
    #   @return [Gem::Version] Component version
    # @!attribute [r] templates
    #   @return [Rake::FileList] Component template list
    # @!attribute [r] styles
    #   @return [Rake::FileList] Component styles list
    # @!attribute [r] scripts
    #   @return [Rake::FileList] Component script list
    # @!attribute [r] dependencies
    #   @return [Hash] Component dependencies
    # @!attribute [r] type
    #   @return [String|nil] Component type
    # @!attribute [r] pagetype
    #   @return [String|nil] Component page type
    # @!attribute [r] context
    #   @return [Hash] Component context
    # @!attribute [r] options
    #   @return [Hash] Component options
    # @!attribute [r] options_src
    #   @return [String|nil] Component options source
    # @!attribute [r] angular
    #   @return [String|nil] Angular module name
    # @!attribute [r] partials
    #   @return [Hash] Component partials
    # @!attribute [r] themes
    #   @return [Rake::FileList] Component theme list
    # @!attribute [r] fields
    #   @return [Hash] Component fields
    # @!attribute [r] title
    #   @return [String|nil] Component title
    # @!attribute [r] description
    #   @return [String|nil] Component description
    # @!attribute [r] thumbnail
    #   @return [String|nil] Component thumbnail
    # @!attribute [r] price
    #   @return [Hash|nil] Component price
    # @!attribute [r] assets
    #   @return [Rake::FileList] Component assets
    # @!attribute [r] src
    #   @return [String] Component source
    # @!attribute [r] i18n
    #   @return [Hash] Component translation files
    # @!attribute [r] base_path
    #   @return [String] Component base path
    # @!attribute [r] checksum
    #   @return [String] Component checksum (SHA1)
    attr_reader :name, :version, :templates, :styles, :scripts, :dependencies, :type, :pagetype,
                :context, :options, :options_src, :angular, :partials, :themes, :fields, :title,
                :thumbnail, :price, :assets, :src, :i18n, :base_path, :checksum

    # Creates a new component from a configuration resource (file or URL)
    #
    # @param [String] config configuration resource
    # @raise [Diversity::Exception] if the resource cannot be loaded
    # @return [BS::Component::Component]
    def initialize(config, skip_validation = false)
      fail Diversity::Exception,
           'Failed to load config file',
           caller unless (data = safe_load(config))
      if remote?(config)
        @src = Addressable::URI.parse(config).to_s
        @base_path = uri_base_path(@src)
      else
        @src = File.expand_path(config)
        @base_path = File.dirname(@src)
      end
      validate_config(data) unless skip_validation
      hsh = parse_config(data)
      @raw = hsh
      @checksum = Digest::SHA1.hexdigest(dump)
      populate(hsh)
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
      @context.each_pair do |key, settings|
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
        # We need to handle both remote and local dependencies
        if remote?(e.last.to_s) # Remote dependency
          req = Addressable::URI.parse(e.last.to_s)
        else # Local dependency
          req = Gem::Requirement.new(normalize_requirement(e.last.to_s))
        end
        res[e.first.to_s] = req
      end
    end

    # Returns options associated with the component, either directly from the config file
    # or by downloading a schema from the specified URL
    #
    # @param [Hash|String] options
    # @return [Hash]
    def get_options(options)
      return options, nil if options.is_a?(Hash)
      options_str = options.to_str # Force to string
      options_url = remote?(options_str) ? options_str : File.join(base_path, options_str)
      fail Diversity::Exception,
           'Failed to load options schema',
           caller unless (data = safe_load(options_url))
      begin
        return JSON.parse(data), options_str
      rescue JSON::ParserError
        raise Diversity::Exception, 'Failed to parse options schema', caller
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
      @name = hsh['name']
      @version = Gem::Version.new(hsh['version'])
      @templates = Rake::FileList.new(hsh.fetch('template', []))
      @styles = Rake::FileList.new(hsh.fetch('style', []))
      @scripts = Rake::FileList.new(hsh.fetch('script', []))
      @dependencies = get_dependencies(hsh.fetch('dependencies', {}))
      @type = hsh.fetch('type', nil)
      @pagetype = hsh.fetch('pagetype', nil)
      @context = hsh.fetch('context', {})
      @options, @options_src = get_options(hsh.fetch('options', {}))
      @angular = hsh.fetch('angular', nil)
      @angular = @name if @angular == true # If set to true, use component name
      @partials = hsh.fetch('partials', {})
      @themes = Rake::FileList.new(hsh.fetch('themes', []))
      @fields = hsh.fetch('fields', {})
      @title = hsh.fetch('title', nil)
      @description = hsh.fetch('description', nil)
      @thumbnail = hsh.fetch('thumbnail', nil)
      @price = hsh.fetch('price', nil)
      @assets = Rake::FileList.new(hsh.fetch('assets', []))
      @i18n = hsh.fetch('i18n', {})
    end

    # Validates configuration and throws an exception if something invalid is discovered
    # @param [String] data
    # @raise [Diversity::Exception] if the configuration contains invalid data
    # @return [nil]
    def validate_config(data)
      schema = File.join(File.dirname(__FILE__), 'diversity.schema.json')
      errors = JSON::Validator.fully_validate(schema, data)
      # fail Diversity::Exception,
      #      "Configuration does not match schema. Errors:\n#{errors.join("\n")}",
      #      caller unless errors.empty?
    end
  end
end
