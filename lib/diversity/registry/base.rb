module Diversity
  # Module containing different kind of registries
  module Registry
    # This class is the superclass of all registry classes
    class Base
      include Common
      # Takes a list of components, loads all of their dependencies and returns a combined list of
      # components. Dependencies will only be included once.
      #
      # @param [Array] components An array of components
      # @return [Array] An expanded array of components
      def expand_component_list(*components)
        components.flatten!
        dependencies = []
        components.each do |component|
          component.dependencies.each_pair do |name, req|
            if req.is_a?(Addressable::URI) || req.is_a?(URI)
              component = load_component(req.to_s)
            elsif req.is_a?(Gem::Requirement)
              component = get_component(name, req)
            else
              fail Diversity::Exception, "Invalid dependency #{dependency}", caller
            end
            fail Diversity::Exception,
                 "Failed to load dependency #{name} [#{req}]",
                 caller unless component
            dependencies.concat expand_component_list(component) unless
              dependencies.any? { |dep|  component == dep  } ||
              components.any?   { |comp| component == comp }
          end
        end
        (dependencies << components).flatten
      end

      # Returns an installed version (or nil if the component does not exist).
      #
      # @param [String] name Component name
      # @param [String|Gem::Version] version Component version. If set to a Gem::Version, only the
      #   exact version is set for. If set to a string it is possible to search for a "fuzzy"
      #   version.
      # @return [Component|nil]
      def get_component(name, version = nil)
        get_matching_components(name, version).first
      end

      # Returns installed components matching the name and version of parameters
      #
      # @param [String] name
      # @param [nil|Gem::Requirement|Gem::Version|String] version
      # @return [Array]
      def get_matching_components(name, version = nil)
        if version.nil? # All versions
          finder = ->(comp) { comp.name == name }
        elsif version.is_a?(Gem::Requirement)
          finder = ->(comp) { comp.name == name && version.satisfied_by?(comp.version) }
        elsif version.is_a?(Gem::Version)
          finder = ->(comp) { comp.name == name && comp.version == version }
        elsif version.is_a?(String)
          req = Gem::Requirement.new(normalize_requirement(version))
          finder = ->(comp) { comp.name == name && req.satisfied_by?(comp.version) }
        else
          fail Diversity::Exception, "Invalid version #{version}", caller
        end
        # Find all matching components and sort them by their version (in descending order)
        installed_components.select(&finder).sort do |first, second|
          first.version <=> second.version
        end
      end

      # Checks whether a component with a specified version is installed.
      #
      # @param [String] name Component name
      # @param [String|Gem::Version|Gem::Requirement] version Component version. If set to a
      #   Gem::Version, only the exact version is set for. If set to a string or a Gem::Requirement
      #   it is possible to search for a "fuzzy" version.
      # @return [true|false]
      def installed?(name, version = nil)
        !get_matching_components(name, version).empty?
      end

      # Loads a remote component
      #
      # @return [Component]
      def load_component(res)
        Component.new(res)
      end
    end
  end
end
