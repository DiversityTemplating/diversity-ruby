# -*- coding: utf-8 -*-
require 'digest/sha1'
require 'eventmachine'
require 'fiber'
require 'json'
require 'json-rpc-client'
require 'rake/file_list'
require 'rubygems/requirement'
require 'rubygems/version'
require 'null_logger'
require_relative 'common'
require_relative 'exception'
require_relative 'json_schema_cache'

module Diversity
  # Class representing an external component
  class Component
    include Common

    MASTER_COMPONENT_SCHEMA =
      'https://raw.githubusercontent.com/DiversityTemplating/' \
      'Diversity/master/validation/diversity.schema.json'

    attr_reader :raw

    DEFAULT_OPTIONS = {
      base_url:      nil,
      base_path:     nil,  # Can be set to something more readily readable than base_url
      logger:        NullLogger.instance,
      validate_spec: false
    }

    # Cmponent configuration
    Configuration =
      Struct.new(
        :name, :version, :templates, :styles, :scripts, :dependencies,
        :type, :pagetype, :context, :settings, :angular,
        :partials, :themes, :fields, :title, :thumbnail, :price,
        :i18n, :description
      )

    Configuration.members.each do |property_name|
      define_method(property_name) { @configuration[property_name] }
    end

    # Creates a new component
    #
    # @param [String|Hash] spec     The diversity.json of the component (as JSON string).
    # @param [Hash]        options  Options: base_url, validate_spec
    #
    # @raise [Diversity::Exception] if the resource cannot be loaded
    #
    # @return [Diversity::Component]
    def initialize(spec, options, registry)
      @configuration = Configuration.new
      @options       = DEFAULT_OPTIONS.keep_merge(options)
      @logger        = @options[:logger]
      @registry      = registry

      # Handle both Hash and String specs
      @raw = (spec.is_a?(String) ? parse_config(spec) : spec)

      if (@options[:validate_spec])
        schema = JsonSchemaCache[
          MASTER_COMPONENT_SCHEMA,
          { validate_spec: @options[:validate_spec] }
        ]

        validation = schema.validate(@raw)
        raise Diversity::Exception,
              "Configuration is not valid:\n" + validation.join("\n"), caller if
          validation.length > 0
      end

      @assets = {}
      populate(@raw)
    end

    # Resolves context in component by asking the API
    #
    # @param [URI|String] backend_url (including any query parameters representing context)
    # @param [Hash] context Context variables
    # @return [Hash]
    def resolve_context(backend_url, context = {})
      # client = JsonRpcClient.new(backend_url.to_s, asynchronous_calls: false)
      resolved_context = {}

      resolved_context[:baseUrl] = @options[:base_url] if @options[:base_url]

      # Check the components context requirements
      @configuration.context.each_pair do |key, settings|
        unless settings.is_a?(Hash)
          resolved_context[key] = settings
          next
        end

        unless settings.key?('type')
          @logger.debug("#{self} has context with no type: #{key}")
          resolved_context[key] = settings
          next
        end

        case settings['type']
        when 'jsonrpc'
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
        when 'prerequisite'
          fail Diversity::Exception, "#{self} needs #{key} in context as prerequisite." unless
            context.key?(key)

          resolved_context[key] = context[key]
        else
          fail Diversity::Exception,
               "#{self} has context #{key} of unhandled type: #{settings['type']}"
        end
      end
      context.keep_merge(resolved_context)
    end

    def <(other)
      (self <=> (other)) == -1
    end

    def <=(other)
      (self <=> (other)) != 1
    end

    def >(other)
      (self <=> (other)) == 1
    end

    def >=(other)
      (self <=> (other)) != -1
    end

    def <=>(other)
      return 0 unless other.is_a?(Diversity::Component)
      return @configuration.name <=> other.name if
        @configuration.name != other.name
      # Return newer versions before older ones
      other.version <=> @configuration.version
    end

    def ==(other)
      name == other.name && version == other.version
    end

    def get_asset(path)
      return @assets[path] if @assets.key?(path)

      if @options[:base_path]
        @assets[path] = safe_load(File.join(@options[:base_path], path))
      else
        @assets[path] = @registry.get_asset(self, path)
      end
    end

    def template_mustache
      templates.map do |template|
        get_asset(template)
      end.join('')
    end

    def scripts
      fail "Can't generate list of script-URL:s with no base_url from registry." unless
        @options[:base_url]

      expand_relative_paths(@options[:base_url], @configuration.scripts)
    end

    def styles
      fail "Can't generate list of style-URL:s with no base_url from registry." unless
        @options[:base_url]

      expand_relative_paths(@options[:base_url], @configuration.styles)
    end

    def base_url
      @options[:base_url]
    end

    def to_s
      "#{@configuration.name}:#{@configuration.version}"
    end

    private

    # Parses a component configuration file
    #
    # @param [String] data configuration data
    # @raise [Diversity::Exception] if the configuration cannot be parsed
    # @return [nil]
    def parse_config(data)
      begin
        JSON.parse(data, symbolize_names: false)
      rescue JSON::ParserError
        raise Diversity::Exception, 'Failed to parse configuration', caller
      end
    end

    # Populates the object with data from different fields in the config file
    #
    # @param [Hash] hsh
    # @return [nil]
    def populate(hsh)
      @configuration.name         = hsh['name']
      @configuration.version      = hsh['version']
      @configuration.templates    = Rake::FileList.new(hsh.fetch('template', []))
      @configuration.styles       = Rake::FileList.new(hsh.fetch('style', []))
      @configuration.scripts      = Rake::FileList.new(hsh.fetch('script', []))
      @configuration.dependencies = hsh.fetch('dependencies', {})
      @configuration.context      = hsh.fetch('context', {})
      settings = hsh.fetch('settings', {})
      schema_options = @options[:validate_spec] ? { validate_spec: true } : {}
      if settings.is_a?(Hash)
        @configuration.settings = JsonSchema.new(settings, nil, schema_options)
      elsif settings.is_a?(String)
        @configuration.settings = JsonSchema.new({}, settings, schema_options)
      else
        @configuration.settings = JsonSchema.new({}, nil, schema_options)
      end
      @configuration.angular = hsh.fetch('angular', nil)
      # If set to true, use component name
      @configuration.angular = @configuration.name if @configuration.angular == true

      #@configuration.title = hsh.fetch('title', nil)
      #@configuration.description = hsh.fetch('description', nil)
      #@configuration.thumbnail = hsh.fetch('thumbnail', nil)
      @configuration.i18n = hsh.fetch('i18n', {})
    end
  end
end
