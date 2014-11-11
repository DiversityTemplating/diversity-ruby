# -*- coding: utf-8 -*-
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
require_relative 'json_schema_cache'

module Diversity
  # Class representing an external component
  class Component
    include Common

    MASTER_COMPONENT_SCHEMA =
      'https://raw.githubusercontent.com/DiversityTemplating/' \
      'Diversity/new-semver-pattern/validation/diversity.schema.json'

    attr_reader :checksum, :raw

    DEFAULT_OPTIONS = {
      base_url:        nil,
      base_path:       nil,  # Can be set to something more readily readable than base_url
      skip_validation: false,
    }

    # Cmponent configuration
    Configuration =
      Struct.new(
        :name, :version, :templates, :styles, :scripts, :dependencies,
        :type, :pagetype, :context, :settings, :angular,
        :partials, :themes, :fields, :title, :thumbnail, :price, :assets,
        :src, :i18n, :description
      )

    Configuration.members.each do |property_name|
      define_method(property_name) { @configuration[property_name] }
    end

    # Creates a new component
    #
    # @param [String] spec     The diversity.json of the component (as JSON string).
    # @param [Hash]   options  Options: base_url, skip_validation
    # 
    # @raise [Diversity::Exception] if the resource cannot be loaded
    # 
    # @return [Diversity::Component]
    def initialize(spec, options)
      @configuration = Configuration.new
      @options = DEFAULT_OPTIONS.keep_merge(options)

      schema = JsonSchemaCache[MASTER_COMPONENT_SCHEMA]
      begin
        schema.validate(spec) unless @options[:skip_validation]
      rescue Diversity::Exception => err
        puts "Bad diversity.json: #{err}\n\n"
      end
      @raw = parse_config(spec)
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
      #client = JsonRpcClient.new(backend_url.to_s, asynchronous_calls: false)
      resolved_context = {}

      # Check the components context requirements
      @configuration.context.each_pair do |key, settings|
        unless settings.is_a?(Hash)
          resolved_context[key] = settings
          next
        end

        unless settings.has_key?('type')
          puts "#{self} has context with no type: #{key}"
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
            context.has_key?(key)
          
          resolved_context[key] = context[key]
        else
          fail Diversity::Exception,
            "#{self} has context #{key} of unhandled type: #{settings['type']}"
        end
      end
      resolved_context
    end

    def <(other_component)
      (self<=>(other_component)) == -1
    end

    def <=(other_component)
      (self<=>(other_component)) != 1
    end

    def >(other_component)
      (self<=>(other_component)) == 1
    end

    def >=(other_component)
      (self<=>(other_component)) != -1
    end

    def <=>(other_component)
      return 0 unless other_component.is_a?(Diversity::Component)
      return @configuration.name <=> other_component.name if
        @configuration.name != other_component.name
      # Return newer versions before older ones
      other_component.version <=> @configuration.version
    end

    def ==(other_component)
      return false unless other_component.is_a?(Diversity::Component)
      @checksum == other_component.checksum
    end

    def get_asset(path)
      if (@options[:base_path])
        full_path = File.join(@options[:base_path], path)
      else
        full_path = "#{@options[:base_url]}/#{path}"
        puts "Attempting to load #{full_path}"
      end
      safe_load(full_path)
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

    def to_s
      "#{@configuration.name}:#{@configuration.version}"
    end

    private

    # Parses requirement strings and creates requirements that matches the requirements
    # of the current component
    # @param [Hash] dependencies part of diversity.json
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
        raise Diversity::Exception, "Failed to parse config file from #{@configuration.src}", caller
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
      settings = hsh.fetch('settings', {})
      if settings.is_a?(Hash)
        @configuration.settings = JsonSchema.new(settings, nil)
      elsif settings.is_a?(String)
        @configuration.settings = JsonSchema.new({}, settings)
      else
        @configuration.settings = JsonSchema.new({}, nil)
      end
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
