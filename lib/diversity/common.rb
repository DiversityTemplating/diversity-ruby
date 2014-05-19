require 'English'
require 'open-uri'

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
      # Watch out for those crazy hats!
      if /^\^(.*)/ =~ req
        version = Gem::Version.new($LAST_MATCH_INFO[1])
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
    # @param [String] res A resource, either a file or an URL
    # @return [String|nil]
    def safe_load(res)
      data = nil
      begin
        Kernel.open(res) do |r|
          data = r.read
        end
      rescue StandardError
      ensure
        # If we got any data, make sure it is a string. Otherwise just return nil.
        data ? data.to_str : data
      end
    end

    # Gets the "parent" of an URL
    #
    # @param [String] s
    # @return [String]
    def uri_base_path(s)
      u = Addressable::URI.parse(s)
      u.path = File.dirname(u.path)
      u.to_s
    end
  end
end
