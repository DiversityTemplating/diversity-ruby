require 'English'
require 'open-uri'

# Main namespace for diversity
module Diversity
  # Namespace for shared methods in the Component namespace
  module Common
    # Returns true if a string matches a remote protocol
    #
    # @param [String] res
    # @return [true|false]
    def remote?(res)
      %r{^(https?|ftp)://.*$} =~ res.to_s
    end

    # Normalizes a requirement string so that it can be parsed by Gem::Requirement
    #
    # @param [String] requirement_string
    # @return [String]
    # https://www.npmjs.org/doc/misc/semver.html
    # http://www.devalot.com/articles/2012/04/gem-versions.html
    def normalize_requirement(requirement_string)
      req = requirement_string.to_s
      if req == '*'
        req = '>0'
      elsif /^\^(.*)/ =~ req
        begin
          req = $LAST_MATCH_INFO[1]
          version = Gem::Version.new(req)
        rescue ArgumentError => err
          # Invalid requirement, try again with all wildcards removed
          begin
            req.gsub!(/[^\d\.]/, '')
            version = version = Gem::Version.new(req)
          rescue ArgumentError
            fail Diversity::Exception, "Invalid requirement #{req}"
          end
        end
        if version < Gem::Version.new('0.1.0')
          req = "=#{version}"
        elsif version < Gem::Version.new('1.0.0')
          req = "~#{version}"
        end
      end

      req.gsub!(/^(\d.*)/, '=\1')
      req.gsub!(/^(~)([^>].*)/, '\1>\2')
      req
    end

    # Safely loads a resource without raising any exceptions. If the resource cannot
    # be fetched, nil is returned.
    #
    # @param [String] resource A resource, either a file or an URL
    # @return [String|nil]
    def safe_load(resource)
      data = nil
      begin
        Kernel.open(resource) do |res|
          data = res.read
        end
      rescue StandardError
      ensure
        # If we got any data, make sure it is a string. Otherwise just return nil.
        data ? data.to_str : data
      end
    end

    # Loads a JSON resource, parses it and returns a Diversity::JsonObject
    #
    # @param[String] resource
    # @param[Class] klass
    def load_json(resource, klass = JsonObject)
      fail "Failed to load JSON from #{resource}" unless (data = safe_load(resource))
      begin
        JsonObject[JSON.parse(data, symbolize_names: false), resource, klass]
      rescue JSON::ParserError
        raise Diversity::Exception, "Failed to parse schema from #{resource}", caller
      end
    end

    # Gets the "parent" of an URL
    #
    # @param [String] url_string
    # @return [String]
    def uri_base_path(url_string)
      url = Addressable::URI.parse(url_string)
      url.path = File.dirname(url.path)
      url.to_s
    end
  end
end
