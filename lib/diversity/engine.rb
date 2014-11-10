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

      # Validate
      debug("\n\n/#{path.join('/')} - #{component.name}:#{component.version}: #{component_settings.inspect}\n")
      validation = JSON::Validator.fully_validate(schema, component_settings)
      debug("Validation failed:\n#{validation.join("\n")}") unless validation.empty?

      # Traverse the component_settings to expand sub-components
      expanded_settings = expand_settings(schema, component_settings, context, path)

      html = render_template(component, context, expanded_settings)
      debug("Rendered: #{html}\n")
      html
    end


    private

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
            return component_settings
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
            # Ignore bad settings; they are warned about in schema validation.
            next unless sub_settings.is_a?(Hash)

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
      #components = @options[:registry].expand_component_list(component)

      #components.each do |component|
        settings.add_component(component)
      #end
      #nil
    end

    class << self
      attr_reader :settings
    end

    # Given a component, a mustache template and some settings, return
    # a rendered HTML string.
    #
    # @param [Diversity::Component] component
    # @param [String] template
    # @param [Hash] component_settings
    #
    # @return [String]
    def render_template(component, context, component_settings)

      mustache_settings = {}
      mustache_settings[:settings]     = component_settings
      mustache_settings[:settingsJSON] =
        component_settings.to_json.gsub(/<\/script>/i, '<\\/script>')

      # Add angularBootstrap, scripts and styles for this level.
      mustache_settings['angularBootstrap'] =
        "angular.bootstrap(document,#{settings.angular.to_json});"
      mustache_settings['scripts'] = settings.scripts
      mustache_settings['styles']  = settings.styles
      mustache_settings['l10n']  = settings.l10n(context['language'])

      template_mustache = component.template_mustache
      return nil unless template_mustache # No need to render empty templates

      # Add data from API
      mustache_settings[:context] = component.resolve_context(context[:backend_url], context)

      # Add some tasty Mustache lambdas
      mustache_settings['currency'] =
        lambda do |text, render|
          # TODO: Fix currency until we decide how to it
          text.gsub(/currency/, 'SEK')
        end
      mustache_settings['gettext'] =
        lambda do |text|
          # TODO: Maybe, maybe not, But later anyway
          text
        end
      mustache_settings['lang'] = lambda do |text|
        # TODO: Fix language until we decide how to set it
        text.gsub(/lang/, context['language'] || 'sv')
      end
      # Return rendered data
      Mustache.render(template_mustache, mustache_settings)
    end
  end
end
