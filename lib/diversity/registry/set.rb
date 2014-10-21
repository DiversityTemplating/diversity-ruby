module Diversity
  module Registry
    # This class represents a set of components guaranteed to not be
      # in conflict
      class Set

        attr_reader :components, :registry

        def initialize(registry)
          @components = []
          @registry = registry
        end

        def <<(component)
          fail "You tried to add a #{component.class} to the component " \
               "set. Please only add components." unless
            component.is_a?(Diversity::Component)
          @components << component
        end

        def to_a
          all_components = self.class.resolve(self)
          groups = all_components.group_by { |c| c.name }
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
          resolved_components
        end

        def self.resolve(set)
          expanded_components = []
          set.components.each do |component|
            dependency_set = self.new(set.registry)
            component.dependencies.each_pair do |name, req|
              # puts "#{component.name} #{component.version} asks for #{name} #{req}"
              if req.is_a?(Addressable::URI) || req.is_a?(URI)
                dependency = set.registry.load_component(req.to_s)
              elsif req.is_a?(Gem::Requirement)
                dependency = set.registry.get_component(name, req)
              else
                fail Diversity::Exception,
                     "Invalid dependency #{name} #{req}", caller
              end
              fail Diversity::Exception,
                   "Failed to load dependency #{name} [#{req}] " \
                   "requested by #{component.name} "\
                   "#{component.version}.", caller unless dependency
              dependency_set << dependency
            end
            expanded_components.concat(resolve(dependency_set))
            expanded_components << component
          end
          expanded_components.uniq
        end
      end
  end
end
