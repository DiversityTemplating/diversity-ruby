module Diversity
  # Class for rendering Diversity components
  class Engine

    DEFAULT_OPTIONS = {
      minify_js: false,
      registry_path: '/home/lasso/components'
    }

    def initialize(options = {})
      @options = options
    end

    # Renders a component
    # @param [Diversity::Component] A diversity component
    # @param [Diversity::JsonObject] A JsonObject representing the settings to apply
    def render(component, settings)
    
    end

  end

end
