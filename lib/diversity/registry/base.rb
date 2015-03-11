module Diversity
  # Module containing different kind of registries
  module Registry
    # This class is the superclass of all registry classes
    class Base
      include Common

      # Checks whether a component with a specified version is available.
      #
      # @param [String] name Component name
      # @param [String|Gem::Version|Gem::Requirement] version Component version. If set to a
      #   Gem::Version, only the exact version is set for. If set to a string or a Gem::Requirement
      #   it is possible to search for a "fuzzy" version.
      # @return [true|false]
      def available?(name, version = nil)
        !get_matching_versions(name, version).empty?
      end

      # Takes a list of components, loads all of their dependencies and returns a combined list of
      # components. Dependencies will only be included once.
      #
      # @param [Array] components An array of components
      # @return [Array] An expanded array of components
      def expand_component_list(*components)
        set = Diversity::ComponentSet.new(self)
        components.flatten.each { |component| set << component }
        set.to_a
      end

      # Returns an installed version (or nil if the component does not exist).
      #
      # @param [String] name Component name
      # @param [String|Gem::Version] version Component version. If set to a Gem::Version, only the
      #   exact version is set for. If set to a string it is possible to search for a "fuzzy"
      #   version.
      # @return [Component|nil]
      def get_component(name, version = nil)
        fail NotImplementedError,
             "#{__method__} must be overridden by subclass.",
             caller
      end

      # Returns components matching the name and version of parameters
      #
      # @param [String] name
      # @param [nil|Gem::Requirement|Gem::Version|String] req
      # @return [Array]
      def get_matching_components(name, req)
        get_matching_versions(name, req).map do |version|
          get_component(name, version)
        end
      end

      private

      # Returns components info matching the name and version of parameters
      #
      # @param [String] name
      # @param [nil|Gem::Requirement|Gem::Version|String] req
      # @return [Array]
      def get_matching_versions(name, req = nil)
        versions = installed_components.find { |cname, _| cname == name }
        return [] if versions.nil?
        if req.nil? # All versions
          finder = ->(_) { true }
        elsif req.is_a?(Gem::Requirement)
          finder = ->(version) { req.satisfied_by?(version) }
        elsif req.is_a?(Gem::Version)
          finder = ->(version) { req == version }
        elsif req.is_a?(String)
          req = Gem::Requirement.new(normalize_requirement(req))
          finder = ->(version) { req.satisfied_by?(version) }
        else
          fail Diversity::Exception, "Invalid requirement #{req}", caller
        end
        versions.last.select(&finder)
      end

      # Init the cache associated with the current registry
      #
      # @param [Hash] options Cache options
      # @return [nil]
      def init_cache(options)
        require 'moneta'
        expires = options.key?(:ttl) ? options[:ttl] : nil
        transformer_options = []
        if options.key?(:transformer)
          if options[:transformer].key?(:key) &&
             !options[:transformer][:key].empty?
            transformer_options[:key] = options[:transformer][:key]
          end
          if options[:transformer].key?(:value) &&
             !options[:transformer][:value].empty?
            transformer_options[:value] = options[:transformer][:value]
          end
        end
        @cache = Moneta.build do
          use     :Expires, expires: expires if expires
          use     :Transformer, transformer_options unless transformer_options.empty?
          use     :Logger
          adapter options[:adapter], options[:adapter_options]
        end
        nil
      end
    end
  end
end
