module Diversity
  module Registry
    # Class representing a compound registry, ie a registry that uses
    # other registries to locate components.
    class Compound < Base
      RegistryEntry = Struct.new(:name, :registry)
      # Constructor
      #
      # @param [Hash] options
      # @return Diversity::Registry::Local
      def initialize(options = {})
        @options = options
        @entries = []
        if @options.key?(:registries) &&
           @options[:registries].is_a?(Array)
          @options[:registries].each do |registry|
            if registry.is_a?(Diversity::Registry::Base)
              name = nil
              registry_obj = registry
            elsif registry.is_a?(Hash) && registry.key?(:registry)
              name = registry[:name]
              registry_obj = registry[:registry]
            elsif registry.is_a?(Array)
              name = registry.first
              registry_obj = registry.last
            else
              fail "Invalid registry #{registry}"
            end
            add_registry(registry_obj, name ? name.to_s : nil)
          end
        end
      end

      # Adds a new registry to the comound registry
      #
      # @param [Diversity::Registry::Base] registry
      # @param [String|nil] name
      def add_registry(registry, name = nil)
        fail "Invalid registry #{registry}" unless
          registry.is_a?(Diversity::Registry::Base)
        @entries << RegistryEntry.new(name, registry)
        nil
      end

      def get_component(name, version = nil)
        @entries.each do |entry|
          return found if (found = entry.registry.get_component(name, version))
        end
        nil
      end

      # Returns a list of installed components
      #
      # @return [Array] An array of Component objects
      def installed_components
        installed = []
        @entries.each do |entry|
          entry.registry.installed_components.each do |component|
            installed << component unless installed.include?(component)
          end
        end
        installed
      end

      def registries
        @entries.reduce([]) do |arr, entry|
          arr << entry.to_h
        end
      end
    end
  end
end
