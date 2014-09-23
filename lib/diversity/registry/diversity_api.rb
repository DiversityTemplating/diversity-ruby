require 'cache'
require 'json'
require 'unirest'

module Diversity
  module Registry
    # Class representing a registry connected to an instance
    # of diversity-api. See
    # https://github.com/DiversityTemplating/diversity-api
    # for further information
    class DiversityApi < Base

      # Default options
      DEFAULT_OPTIONS = {
        backend_url: nil,
        skip_validation: false
      }

      def initialize(options = {})
        @options = DEFAULT_OPTIONS.merge(options)
        fail 'Invalid backend URL!' unless ping_ok
      end

      # Returns a list of installed components
      #
      # @return [Array] An array of Component objects
      def installed_components
        component_objs = []
        components = call_api('components/')
        components.each do |component|
          version_objs = get_installed_versions(component[:name])
          version_objs.each do |version_obj|
            begin
              component_objs <<
                Component.new(
                  File.join(
                    @options[:backend_url], 'components', component[:name],
                    version_obj.to_s, 'files', 'diversity.json'
                  ),
                  @options[:skip_validation]
                )
            rescue Exception => err
              next # Silently ignore non-working components
            end
          end
        end
        component_objs
      end

      private

      # Calls the diversity REST Api and parses the response
      #
      # @param [Array] path
      # @return Hash
      def call_api(*path)
        # TODO: Caching
        url = @options[:backend_url]
        path.each do |part|
          url = File.join(url, part)
        end
        response = Unirest.get(url)
        fail 'Error when calling API' unless response.code == 200
        fail 'Invalid content type' unless response.headers[:content_type] == 'application/json'
        JSON.parse(response.raw_body, symbolize_names: true)
      end

      # Returns a list of available versions for a specific component
      #
      # @param [String] component_name
      # @return [Array]
      def get_installed_versions(component_name)
        version_objs = []
        versions = call_api('components', component_name)
        versions.each do |version|
          begin
            version_objs << Gem::Version.new(version)
          rescue ArgumentError
            next # Ignore malformed version numbers
          end
        end
        version_objs.sort
        # TODO: Talk to David about default versions
        # version_objs << Gem::Version.new('0.0.1') if version_objs.empty?
        version_objs
      end

      # Checks whether the diversity API is live and kicking.
      #
      # @return [true|false]
      def ping_ok
        return false unless @options[:backend_url]
        response = Unirest.get(@options[:backend_url])
        response.code == 200 &&
          response.raw_body == 'Welcome to Diversity Api'
      end
    end
  end
end
