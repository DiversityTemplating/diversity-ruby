module Diversity
  # Class for rendering Diversity components
  class Engine

    DEFAULT_OPTIONS = {
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
    def render(component, settings)
      # 1. Check that the settings are applicable for the component
      validate_settings(component.settings, settings)
      # 2. Extract the components needed by the main components (dependencies)
      components = @registry.expand_component_list(component)
      # 3. Extract subcomponents from the settings
      subcomponents = get_subcomponents(component, settings)
      subcomponents.each do |sub|
        p sub.first.name + "(#{sub.first.version})"
        p sub.last
      end
      # 4. Make sure that all components are available
      # 5. Iterate through the list of components (from the "innermost") and render them
      # 6. Attach the rendered component to its parent (as a special key) until we reach the "topmost" component
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
      new_keys = []
      component_keys.each do |key|
        new_keys << key.reject { |e| e == 'properties' || e == 'items' }
      end
      new_keys.each do |key|
        components = extract_setting(key, settings)
        unless components.nil?
          components.each do |c|
            comp = @registry.get_component(c['component'])
            fail "Cannot load component #{c['component']}" if comp.nil?
            subcomponents << [comp, c['settings']]
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

  end

end
