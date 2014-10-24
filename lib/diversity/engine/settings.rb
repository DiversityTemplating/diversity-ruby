module Diversity
  class Engine
    # A simple wrapper for the context used when rendering
    class Settings

      def initialize(registry)
        @component_set = Diversity::ComponentSet.new(registry)
        @paths = {}
      end

      def add_component(component, path)
        @component_set << component
        @paths[component.checksum] = path
      end

      def angular
        @component_set.to_a.inject([]) do |angular, comp|
          if comp.angular
            angular << comp.angular
          else
            angular
          end
        end
      end

      def scripts
        @component_set.to_a.inject([]) do |scripts, comp|
          scripts.concat(
            Diversity::Engine.expand_relative_paths(
              @paths[comp.checksum], comp.scripts
            )
          )
        end
      end

      def styles
        @component_set.to_a.inject([]) do |styles, comp|
          styles.concat(
            Diversity::Engine.expand_relative_paths(
              @paths[comp.checksum], comp.styles
            )
          )
        end
      end
    end
  end
end
