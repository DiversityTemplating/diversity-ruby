module Diversity
  class Engine
    # A simple wrapper for the context used when rendering
    class Settings

      def initialize(registry)
        @component_set = Diversity::ComponentSet.new(registry)
      end

      def add_component(component)
        @component_set << component
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

      def l10n(langcode)
        @component_set.to_a.inject([]) do |l10n, comp|
          if comp.i18n &&
             comp.i18n.key?(langcode) &&
             comp.i18n[langcode].key?('view') # i18n will be changed to l10n later
            if (data = comp.get_asset(comp.i18n[langcode]['view']))
              l10n << {
                'component' => comp.name,
                'messages'  => data
              }
            else
              puts "Failed to load #{comp.i18n[langcode]['view']}"
              l10n
            end
          else
            l10n
          end
        end
      end

      def scripts
        @component_set.to_a.map { |comp| comp.scripts }.flatten
      end

      def styles
        @component_set.to_a.map { |comp| comp.styles }.flatten
      end
    end
  end
end
