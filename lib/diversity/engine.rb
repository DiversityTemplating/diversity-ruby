# -*- coding: utf-8 -*-
require 'mustache'
require_relative 'engine/settings'

module Diversity
  # Class for rendering Diversity components
  class Engine
    extend Common

    @settings = {}

    # Default options for engine
    DEFAULT_OPTIONS = {
      backend_url: nil, # Optional, might be overridden in render
      minify_js: false,
      public_path: nil,
      public_path_proc: nil,
      registry: nil
    }

    def initialize(options = {})
      @options = DEFAULT_OPTIONS.merge(options)
      @debug_level = 0

      # Ensure that we have a valid registry to work against
      fail 'Cannot run engine without a valid registry!' unless
        @options[:registry].is_a?(Registry::Base)
    end

    # Renders a component
    # 
    # @param [Diversity::Component] component
    # @param [Hash]   context   Context to render in.
    # @param [Hash]   settings  Settings for this component rendering.
    # @param [Array]  path      Array representing json path from root.
    # 
    # @return [Hash|String]
    def render(component, context = {}, component_settings = {}, path = [])
      add_component(component)

      # Get component schema
      schema = component.settings.data

      debug("/#{path.join('/')} - #{component.name}:#{component.version}:\n", 1)
      debug("Settings original: #{component_settings}\n")

      # Traverse the component_settings to expand sub-components
      expanded_settings = expand_settings(schema, component_settings, context, path)

      #debug("Settings expanded: #{expanded_settings}\n")

      templates = component.templates.map do |template|
        self.class.expand_relative_paths(component.base_path, template)
      end

      html = templates.map do |template|
        render_template(component, template, context, expanded_settings)
      end.join('')

      debug("Rendered:\n#{html}\n\n", -1)

      html
    end

    # Expands the component_settings, replacing components with HTML and adding components to set
    #
    # @return expanded_settings
    def expand_settings(schema, component_settings, context = {}, path = ())
      if component_settings.is_a?(Hash)
        expanded_settings = {}

        component_settings.each_pair do |key, sub_settings|
          sub_path = path.clone
          sub_path << key

          # Get the sub_schema from schema.  This only works with simple schema, should really be
          # done with a json-schema-lib that can expand, chose one-of etc.
          if schema.has_key?('properties') and schema['properties'].has_key?(key)
            sub_schema = schema['properties'][key]
          elsif schema.has_key?('additionalProperties')
            sub_schema = schema['additionalProperties']
          else
            #fail "No properties/#{key} at /#{path.join('/')} in " + JSON.pretty_generate(schema)
            puts " FAIL: No properties/#{key} at /#{path.join('/')} in " +
              JSON.pretty_generate(schema)
            return
          end

          if sub_schema.has_key?('format') and sub_schema['format'] == 'diversity'
            # Replace the setting with HTML output from the component
            version         = sub_settings.has_key?('version' ) ? sub_settings['version' ] : nil
            subsub_settings = sub_settings.has_key?('settings') ? sub_settings['settings'] : nil
            sub_component   = get_component(sub_settings['component'], version)

            expanded_settings[key] =
              { componentHTML: render(sub_component, context, subsub_settings, sub_path) }
          else
            expanded_settings[key] = expand_settings(sub_schema, sub_settings, context, sub_path)
          end
        end
      elsif component_settings.is_a?(Array)
        expanded_settings = []

        # Pick schema for array items from schema items.  …this is also simplified…
        sub_schema = schema['items']

        # @todo Check additionalItems

        component_settings.each_with_index do |sub_settings, index|
          sub_path = path.clone
          sub_path  << index

          if sub_schema.has_key?('format') and sub_schema['format'] == 'diversity'
            # Replace the setting with HTML output from the component
            version         = sub_settings.has_key?('version' ) ? sub_settings['version' ] : nil
            subsub_settings = sub_settings.has_key?('settings') ? sub_settings['settings'] : nil
            sub_component   = @options[:registry].get_component(sub_settings['component'], version)

            expanded_settings <<
              { componentHTML: render(sub_component, context, subsub_settings, sub_path) }
            #debug("Rendered: #{expanded_settings.last}")
          else
            expanded_settings << expand_settings(sub_schema, sub_settings, context, sub_path)
          end
        end
      else
        expanded_settings = component_settings
      end

      expanded_settings
    end


    private

    # Returns the default rendering context for the current engine
    #
    # @return [Hash]
    def settings
      self.class.settings[self] ||= Settings.new(@options[:registry])
    end

    # Deletes the rendering context for the current engine
    def delete_settings
      self.class.settings.delete(self)
    end

    def debug(msg, debug_delta = 0)
      @options[:debug_logger] << '  ' * @debug_level + msg if @options[:debug_logger]
      @debug_level += debug_delta
    end

    def public_path(component)
      # If the user has provided a Proc for the public path, call it
      proc = @options[:public_path_proc]
      return proc.call(self, component) if proc
      # If the user has provided a String for the public path, use that
      path = @options[:public_path]
      return File.join(path, component.name, component.version.to_s) if path
      # Use the component's base path by default
      File.join(component.base_path, component.name, component.version.to_s)
    end

    def get_component(name, version = nil)
      component = @options[:registry].get_component(name, version)
      fail "No component from #{sub_settings['component']}" unless sub_component
      add_component(component)
    end

    # Update the rendering context with data from the currently
    # rendering component.
    #
    # @param [Array] An array of Diversity::Component objects
    # @return [nil]
    def add_component(component)
      components = @options[:registry].expand_component_list(component)
      
      components.each do |component|
        settings.add_component(component, public_path(component))
      end
      nil
    end

    class << self
      attr_reader :settings
    end

    # Merges all content in a single key to a single string.
    #
    # @param [Hash] contents
    # @return [Hash]
    def self.merge_contents(contents)
      contents.each_with_object({}) do |(key, value), hsh|
        hsh[key] = value.join('')
      end
    end

    # Make sure that the provided settings are valid
    def validate_settings(available_settings, requested_settings)
      begin
        available_settings.validate(requested_settings)
      rescue
        # failed to validate settings. now what?
        debug('Oops, failed to validate settings')
      end
    end

    def self.deep_merge(obj1, obj2)
      if obj1.is_a?(Array) && obj2.is_a?(Array)
        obj1.concat(obj2)
      elsif obj1.is_a?(Hash) && obj2.is_a?(Hash)
        obj1.merge(obj2) do |_, val1, val2|
          if (val1.is_a?(Array) && val2.is_a?(Array)) ||
             (val1.is_a?(Hash) && val2.is_a?(Hash))
            deep_merge(val1, val2)
          else
            val2
          end
        end
      else
        obj2
      end
    end

    # Given a component, a mustache template and some settings, return
    # a rendered HTML string.
    #
    # @param [Diversity::Component] component
    # @param [String] template
    # @param [Hash] component_settings
    # 
    # @return [String]
    def render_template(component, template, context, component_settings)

      mustache_settings = {}
      mustache_settings[:settings]     = component_settings
      mustache_settings[:settingsJSON] =
        component_settings.to_json.gsub(/<\/script>/i, '<\\/script>')

      # Add angularBootstrap, scripts and styles for this level.
      mustache_settings['angularBootstrap'] =
        "angular.bootstrap(document,#{settings.angular.to_json});"
      mustache_settings['scripts'] = settings.scripts
      mustache_settings['styles']  = settings.styles

      template_data = self.class.safe_load(template)
      return nil unless template_data # No need to render empty templates
      # Add data from API
      rcontext = component.resolve_context(context[:backend_url], context)
      rcontext = self.class.deep_merge(mustache_settings, {context: rcontext})
      # Add some tasty Mustache lambdas
      rcontext['currency'] =
        lambda do |text, render|
          # TODO: Fix currency until we decide how to it
          text.gsub(/currency/, 'SEK')
        end
      rcontext['gettext'] =
        lambda do |text|
          # TODO: Maybe, maybe not, But later anyway
          text
        end
      rcontext['lang'] = lambda do |text|
        # TODO: Fix language until we decide how to set it
        text.gsub(/lang/, 'sv')
      end
      # Return rendered data
      Mustache.render(template_data, rcontext)
    end
  end
end
