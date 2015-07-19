# coding: utf-8
require 'English'
require 'open-uri'
require 'open_uri_redirections'

# Main namespace for diversity
module Diversity
  # Namespace for shared methods in the Component namespace
  module Common
    # Returns true if a string matches a remote protocol
    #
    # @param [String] res
    # @return [true|false]
    def remote?(res)
      %r{//.*$} =~ res.to_s
    end

    # Create a list of absolute paths from a base path and a list of
    # relative paths.
    #
    # @param [String] base_path
    # @param [Enumerable|String] file_list
    # @return [Array]
    def expand_relative_paths(base_path, file_list)
      return nil if file_list.nil?
      if file_list.respond_to?(:each)
        file_list.map do |file|
          res = file.to_s
          remote?(res) ? res : "#{base_path}/#{res}"
        end
      else
        f = file_list.to_s
        return file_list if f.empty?
        remote?(f) ? f : File.join(base_path, f)
      end
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
        rescue ArgumentError
          # Invalid requirement, try again with all wildcards removed
          begin
            req.gsub!(/[^\d\.]/, '')
            version = version = Gem::Version.new(req)
          rescue ArgumentError
            raise Diversity::Exception, "Invalid requirement #{req}"
          end
        end
        if version < Gem::Version.new('0.1.0')
          req = "=#{version}"
        elsif version < Gem::Version.new('1.0.0')
          req = "~#{version}"
        end
      end

      req.gsub!(/^(\d+\.\d+)\.\d+$/, '~>\1') # ^1.0.0  =>  ~>1.0
      req.gsub!(/^(\d+)\.\d+$/, '~>\1')      # ^1.0    =>  ~>1
      req.gsub!(/^(\d+)$/, '\1')             # ^1      =>  1
      req.gsub!(/^(~)([^>].*)/, '\1>\2') # ??
      req
    end

    # Safely loads a resource without raising any exceptions. If the resource cannot
    # be fetched, nil is returned.
    #
    # @param [String] resource A resource, either a file or an URL
    # @return [String|nil]
    def safe_load(resource)
      resource = "https:#{resource}" if resource[0..1] == '//' # Use HTTPS for semi-absolute urls
      data = nil
      begin
        Kernel.open(resource, allow_redirections: :safe) do |res|
          # We will only handle UTF-8 encoded data for now
          # so lets pretend that all data is UTF-8 regardless of what
          # the original source claims
          if res.external_encoding != Encoding::UTF_8
            res.set_encoding(Encoding::UTF_8)
          end
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
    # @param [String] resource
    # @param [Class] klass
    # @param [Hash] options
    def load_json(resource, klass = JsonObject, options = {})
      fail "Failed to load JSON from #{resource}" unless (data = safe_load(resource))
      begin
        JsonObject[JSON.parse(data, symbolize_names: false), resource, klass, options]
      rescue JSON::ParserError
        raise Diversity::Exception, "Failed to parse schema from #{resource}", caller
      end
    end

    # Loads several resources in parallell
    #
    # @param [Enumerable] resources
    # @param [Hash] options
    # @return [Hash]
    def parallell_load(resources, options = {})
      return if resources.empty?
      require 'threadify'
      options[:strategy] = :each unless options.key?(:strategy)
      options[:threads] = resources.length unless options.key?(:threads)
      data = {}
      resources.threadify(options) do |resource|
        # Never load the same resource more than once
        next if data.key?(resource)
        if (content = safe_load(resource))
          data[resource] = content
        else
          p "Failed to load #{resource}"
        end
      end
      data
    end
  end
end
