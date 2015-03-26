module Diversity
  class ComponentSet
    # This class represents a set of components guaranteed to not be
    # in conflict

    attr_reader :components, :registry

    def initialize(registry)
      @components = []
      @registry = registry
    end

    def <<(component)
      fail "You tried to add a #{component.class} to the component " \
           "set. Please only add components." unless
        component.is_a?(Diversity::Component)

      # Don't keep multiple instances in the array!
      return @components if @components.include?(component)

      # Add depencencies
      component.dependencies.each_pair do |name, req|
        dependency = registry.get_component(name, req)

        fail Diversity::Exception,
          "Failed to load dependency #{name}:#{req} " \
          "requested by #{component}.", caller unless dependency
        self << dependency
      end

      # Add component itself.  Must be done after dependencies.
      @components << component

      # Resolve different versions of a component
      groups = @components.group_by { |c| c.name }
      resolved_components = []
      groups.each_pair do |k, v|
        if v.length > 1
          # We have more than one version. Resolve conflicts here
          print "More than one version of component #{k} requested "
          puts '[' << v.map { |c| c.version }.join(', ') << '].'
          latest = v.max_by { |comp| comp.version }
        else
          latest = v.first
        end
        # puts "Using #{latest.name} #{latest.version}"
        resolved_components << latest
      end

      # Overwrite list of components with no conflicts
      @components = resolved_components
    end

    def to_a
      @components
    end
  end
end
