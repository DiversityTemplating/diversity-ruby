# -*- coding: utf-8 -*-
require 'mustache'
require 'tmpdir'
require 'null_logger'
require_relative 'engine/settings'

module Diversity
  # Class for rendering Diversity components
  class Engine
    extend Common

    @settings = {}

    # Default options for engine
    DEFAULT_OPTIONS = {
      backend_url: nil, # Optional, might be overridden in render
      minification: { # Only used when minification is active
        base_dir: File.join(Dir.tmpdir, 'diversity', 'minified'),
        base_url: '/minified',
        minify_css: false,
        minify_js: false,
        minify_remotes: false
      },
      cache: {ttl: 60},
      registry: nil,
      logger: NullLogger.instance,
      validate_settings: false
    }

    def initialize(options = {})
      @options = DEFAULT_OPTIONS.keep_merge(options)
      @debug_level = 0
      @logger = @options[:logger]

      ttl = @options[:cache][:ttl]
      @cache = Moneta.build do
        use :Expires, expires: ttl
        adapter :Memory
      end

      # Ensure that we have a valid registry to work against
      fail 'Cannot run engine without a valid registry!' unless
        @options[:registry].is_a?(Registry::Base)
    end

    attr_reader :options

    # Renders a component
    #
    # @param [Hash]   settings  What to render; a Hash with component, version, settings.
    # @param [Hash]   context   Context to render in.
    # @param [Array]  path      Array representing json path from root.
    #
    # @return [Array] Array of Components and String
    def render(settings, context = {}, path = [])
      cache_key = "#{settings.to_json}:#{context.to_json}"
      return @cache[cache_key] if @cache.key?(cache_key)

      # We are only interrested in the components used from this point and down.
      version   = settings.key?('version') ? settings['version'] : nil
      component = @options[:registry].get_component(settings['component'], version)
      component_settings = settings.key?('settings') ? settings['settings'] : nil

      components = [component]

      # Get component schema
      schema = component.settings

      # Validate if told to and someone could see it
      if @options[:validate_settings]
        validation = schema.validate(component_settings)
        @logger.warn("Validation failed:\n#{validation.join("\n")}") unless validation.empty?
      end

      # Traverse the component_settings to expand sub-components
      new_components, expanded_settings = expand_settings(
        schema.data, component_settings, context, path, component
      )
      components.concat(new_components)

      html = render_template(component, context, expanded_settings, path, components)
      @cache[cache_key] = [components, html]
    end

    private

    # Expands the component_settings, replacing components with HTML and adding components to set
    #
    # @return expanded_settings
    def expand_settings(schema, component_settings, context = {}, path = [], last_component)
      components = []

      if component_settings.is_a?(Hash)
        expanded_settings = {}

        component_settings.each_pair do |key, sub_settings|
          sub_path = path.clone
          sub_path << key

          # Get the sub_schema from schema.  This only works with simple schema, should really be
          # done with a json-schema-lib that can expand, chose one-of etc.
          if schema.key?('properties') && schema['properties'].key?(key)
            sub_schema = schema['properties'][key]
          elsif schema.key?('additionalProperties')
            sub_schema = schema['additionalProperties']
          else
            @logger.warn(
              "Could not add setting #{key} to #{last_component} at /#{path.join('/')} " \
              'in ' + JSON.pretty_generate(schema)
            )
            return [components, component_settings]
          end

          if sub_schema.key?('format') && sub_schema['format'] == 'diversity'
            # Add componentHTML
            new_components, html = render(sub_settings, context, sub_path)
            components.concat(new_components)
            expanded_settings[key] = { componentHTML: html }
          else
            new_components, expanded_settings[key] =
              expand_settings(sub_schema, sub_settings, context, sub_path, last_component)
            components.concat(new_components)
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

          # Ignore bad settings; they are warned about in schema validation.
          next unless sub_schema.is_a?(Hash)

          if sub_schema.key?('format') && sub_schema['format'] == 'diversity'
            # Ignore bad settings; they are warned about in schema validation.
            next unless sub_settings.is_a?(Hash)

            # Add componentHTML
            new_components, html = render(sub_settings, context, sub_path)
            expanded_settings << { componentHTML: html }
            components.concat(new_components)
          else
            new_components, subsettings =
              expand_settings(sub_schema, sub_settings, context, sub_path)
            expanded_settings << subsettings
            components.concat(new_components)
          end
        end
      else
        expanded_settings = component_settings
      end

      [components, expanded_settings]
    end

    def get_component(name, version = nil)
      component = @options[:registry].get_component(name, version)
      fail "No component from #{sub_settings['component']}" unless component
      component
    end

    class << self
      attr_reader :settings
    end

    # Given a component, a mustache template and some settings, return
    # a rendered HTML string.
    #
    # @param [Diversity::Component]  component
    # @param [Hash]                  context
    # @param [Hash]                  component_settings
    # @param [Array]                 path
    # @param [Array]                 components
    #
    # @return [String]  html
    def render_template(component, context, component_settings, path, components)
      mustache_settings = {}
      mustache_settings[:settings]     = component_settings
      mustache_settings[:settingsJSON] =
        component_settings.to_json.gsub(/<\/script>/i, '<\\/script>')

      # Add angularBootstrap, scripts and styles (top level only)
      if path.empty?
        set = Diversity::ComponentSet.new(@options[:registry])
        components.each { |component| set << component }
        @logger.debug { "Rendering mustache with: #{components.map {|c| c.to_s}}" }

        settings = Diversity::Engine::Settings.new(set, @logger)

        mustache_settings['angularBootstrap'] =
          "angular.bootstrap(document,#{settings.angular.to_json});"

        # Should we use minification?
        if @options[:minification][:minify_css] || @options[:minification][:minify_js]
          minify_options = @options[:minification].dup
          minify_options[:filename] = context[:minify_filename]
        end
        if @options[:minification][:inline_js]
          mustache_settings['minifiedJs'] = settings.concatenated_scripts(minify_options).
            gsub(/<\/script>/i, '<\\/script>')
        elsif @options[:minification][:minify_js]
          mustache_settings['scripts'] = settings.minified_scripts(minify_options)
        else
          mustache_settings['scripts'] = settings.scripts
        end
        if @options[:minification][:minify_css]
          mustache_settings['styles'] = settings.minified_styles(minify_options)
        else
          mustache_settings['styles'] = settings.styles
        end

        begin
          mustache_settings[:l10n] = settings.l10n(context[:language])
        rescue Encoding::UndefinedConversionError => e
          raise Diversity::Exception,
                "Bad json in l10n of #{component}: #{e}\n" \
                "We have collected: #{settings.l10n(context[:language]).inspect}\n" \
                "With system encoding: #{Encoding.default_external}"
        end
      end

      template_mustache = component.template_mustache
      return nil unless template_mustache # No need to render empty templates

      # Add data from API
      mustache_settings[:context] = component.resolve_context(context[:backend_url], context)
      mustache_settings[:baseUrl] = component.base_url

      # Add some tasty Mustache lambdas
      mustache_settings['currency'] =
        lambda do |text|
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
        text.gsub(/lang/, context[:language] || 'sv')
      end

      @logger.info("Rendering #{component}\n") # with mustache:\n#{mustache_settings}\n\n"

      # Return rendered data
      Mustache.render(template_mustache, mustache_settings)
    end
  end
end
