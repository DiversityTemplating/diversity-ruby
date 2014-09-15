require 'mustache'

module Diversity
  # Class for rendering Diversity components
  class Engine

    include Common

    DEFAULT_OPTIONS = {
      backend_url: 'https://www.textalk.se/backend/jsonrpc',
      minify_js: false,
      registry_path: '/home/lasso/components'
    }

    def initialize(options = {})
      @options = DEFAULT_OPTIONS.merge(options)
      @registry = Registry.new(@options[:registry_path])
    end

    # Renders a component
    # @param [Diversity::Component] A diversity component
    # @param [Diversity::JsonObject] A JsonObject representing the settings to apply
    def render(component, settings, key = [])
      puts "Rendering #{key.inspect} (#{component.name} (#{component.version})"
      fail "First argument must be a Diversity::Component, but you sent a #{component.class}" unless component.is_a?(Component)
      fail "Second argument must be a Diversity::JsonObject, but you sent a #{settings.class}" unless settings.is_a?(JsonObject)
      # 1. Check that the settings are applicable for the component
      validate_settings(component.settings, settings)
      # 2. Extract the components needed by the main components (dependencies)
      components = @registry.expand_component_list(component)
      # 3. Extract subcomponents from the settings
      # 4. Make sure that all components are available
      # 5. Iterate through the list of components (from the "innermost") and render them
      
      templatedata = {}
      subcomponents = get_subcomponents(component, settings)
      subcomponents.each do |sub|
        templatedata[sub[2]] ||= []
        templatedata[sub[2]] << render(sub[0], sub[1], sub[2])[sub[2]]
      end

      templates = component.templates.map { |t| expand_component_paths(component.base_path, t) }

      # TODO! Merge templatedata from subcomponents into the context of the current template

      templates.each do |template|
        templatedata[key] = render_template(component, template, settings)
      end

      p templatedata.keys
      
      # 6. Attach the rendered component to its parent (as a special key) until we reach the "topmost" component
      templatedata
    end

    private

    # Make sure that the provided settings are valid
    def validate_settings(available_settings, requested_settings)
      begin
        available_settings.validate(requested_settings)
      rescue
        # failed to validate settings. now what?
        puts 'Oops, failed to validate settings'
      end
    end

    def get_subcomponents(component, settings)
      subcomponents = []
      component_keys = component.settings.select do |node|
        node.last['type'] == 'object' && node.last['format'] == 'diversity'
      end.map { |node| node.first }
      return [] if component_keys.empty?
      new_keys = []
      component_keys.each do |key|
        new_keys << key.reject { |e| e == 'properties' || e == 'items' }
      end
      # Sort by key length first and then by each key
      new_keys = new_keys.sort do |one_obj, another_obj|
        sort_by_key(one_obj, another_obj)
      end
      new_keys.each do |key|
        components = extract_setting(key, settings)
        unless components.nil?
          components.each do |c|
            comp = @registry.get_component(c['component'])
            fail "Cannot load component #{c['component']}" if comp.nil?
            subcomponents << [comp, JsonObject[c['settings']], key]
          end
        end
      end
      subcomponents
    end

    # Given a schema key, returns the setting associated with that key
    # @param [Array] key
    # @param [Diversity::JsonSchema]
    # @return [Array|nil]
    def extract_setting(key, settings)
      k = key.dup
      last = k.pop
      data = settings[k]
      return nil if data.nil? || data.empty?
      data = data[last]
      return nil if data.nil? || data.empty?
      data
    end

    def expand_component_paths(base_path, file_list)
      return nil if file_list.nil?
      if file_list.respond_to?(:each)
        file_list.map do |file|
          f = file.to_s
          remote?(f) ? f : File.join(base_path, f)
        end
      else
        f = file_list.to_s
        return file_list if f.empty?
        remote?(f) ? f : File.join(base_path, f)
      end
    end

    def render_template(component, template, settings)
      template_data = safe_load(template)
      return nil if template_data.nil? # No need to render empty templates
      # Add data from API
      context = component.resolve_context(@options[:backend_url], component.context)
      # Add data from settings (only "TOP LEVEL)"
      applicable = settings.select do |node|
        node.first.length < 2
      end.map { |e| e.last }.first
      settings = Hash.new
      settings[:settings] = Hash.new
      applicable.each_pair do |k, v|
        settings[:settings][k.to_sym] = v
      end
      settings = settings.merge(context)
      # Return rendered data
      Mustache.render(template_data, settings)
    end

    # Sort by longest key length first and then by each key
    def sort_by_key(one_obj, another_obj)
      len_cmp = another_obj.length  <=> one_obj.length
      return len_cmp if len_cmp.nonzero?
      one_obj.each_with_index do |key, index|
        key_cmp = another_obj[index] <=> key 
        return key_cmp if key_cmp.nonzero?
      end
      0
    end

  end

end
