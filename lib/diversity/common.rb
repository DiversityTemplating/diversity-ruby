require 'open-uri'

module Diversity

  # Namespace for shared methods in the Component namespace
  module Common

    # Expands a single path or a list of patch to form an absolute URL or an absoluet file path
    #
    # @param [String] base_path
    # @param [Enumerable|String|nil] file_list
    # @return [Enumerable|String|nil]
    def expand_paths(base_path, file_list)
      return nil if file_list.nil?
      if file_list.respond_to?(:each)
        file_list.collect do |file|
          f = file.to_s
          is_remote?(f) ? f : File.join(base_path, f)
        end
      else
        f = file_list.to_s
        return file_list if f.empty?
        is_remote?(f) ? f : File.join(base_path, f)
      end
    end

    # Returns true if a string matches a remote protocol
    #
    # @param [String] res
    # @return [true|false]
    def is_remote?(res)
      /^(https?|ftp):\/\/.*$/ =~ res.to_s
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
        version = Gem::Version.new($~[1])
        if version < Gem::Version.new("0.1.0")
          req = "=#{version.to_s}"
        else version < Gem::Version.new("1.0.0")
          req = "~#{version.to_s}"
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

