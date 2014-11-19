# -*- coding: utf-8 -*-
require 'fileutils'
require 'addressable/uri'
require 'fileutils'
require_relative '../common.rb'
require_relative '../component.rb'
require_relative '../exception.rb'

module Diversity
  module Registry
    # Class representing a list of locally installed Component objects
    class Local < Base
      # Glob representing locally installed component configurations
      DEFAULT_OPTIONS = {
        base_path: nil,
        base_url:  nil,
        mode:      :default,
        cache_options: {
          adapter: :Memory,
          adapter_options: {},
          transformer: {
            key: [],
            value: []
          },
          ttl: 3600
        },
        skip_validation: false
      }

      GLOB = '*/*/diversity.json'

      # Constructor
      #
      # @param [String] base_path
      # @param [Hash] options
      # @return Diversity::Registry::Local
      def initialize(options = {})
        @options = DEFAULT_OPTIONS.keep_merge(options)
        @options[:base_path] = File.expand_path(@options[:base_path])
        fileutils.mkdir_p(@options[:base_path]) unless File.exist?(@options[:base_path])
        init_cache(@options[:cache_options])
      end

      def base_path
        @options[:base_path]
      end

      def get_component(name, version = nil)
        cache_key = "component:#{name}:#{version}"
        return @cache[cache_key] if @cache.key?(cache_key)

        name_dir = File.join(@options[:base_path], name)

        # If the component isn't available locally, let someone else try.
        return super unless Dir.exist?(name_dir)

        Dir.chdir(name_dir) do
          if File.exist?('diversity.json')
            # If there's a diversity.json right here, this is a development package.
            base_url =  @options[:base_url] ? "#{@options[:base_url]}/#{name}" : nil
            @cache[cache_key] = get_component_by_dir(name_dir)
          else
            requirement =
              (version.nil? or version == '*') ? Gem::Requirement.default :
              version.is_a?(Gem::Requirement)  ? version                  :
              Gem::Requirement.create(normalize_requirement(version))

            # Select highest matching version.
            version_path =
              Dir.glob('*').map { |version_path| Gem::Version.new(version_path) }.
              select {|version_obj| requirement.satisfied_by?(version_obj) }.
              sort.last.to_s

            base_url =  @options[:base_url] ? "#{@options[:base_url]}/#{name}/#{version_path}" : nil
            @cache[cache_key] = get_component_by_dir(File.join(name_dir, version_path), base_url)
          end
        end
      end

      def get_component_by_dir(dir, base_url = nil)
        Dir.chdir(dir) do
          fail "No component in #{dir}" unless File.exist?('diversity.json')

          spec    = File.read('diversity.json')
          options = {
            skip_validation: @options[:skip_validation],
            base_url:        base_url,
            base_path:       dir,
          }
          Component.new(spec, options)
        end
      end

      # Returns a list of locally installed components
      #
      # @return [Hash] A hash of component_name => [component_versions]
      def installed_components
        cache_key = "installed_components_#{object_id}"
        return @cache[cache_key] if @cache.key?(cache_key)
        Dir.chdir(@options[:base_path]) do
          data =
            Dir.glob(GLOB).reduce({}) do |res, cfg|
              begin
                component, version, _ = cfg.split(File::SEPARATOR)
                res[component] = [] unless res.key?(component)
                res[component] << Gem::Version.new(version)
              rescue Diversity::Exception => e
                puts "Caught an exception trying to put #{cfg} in list of installed components."
                p e
              end
              res
            end.each_pair do |component, versions|
              versions.sort! { |a, b| b <=> a }
            end
          @cache.store(cache_key, data, expires: 600)
        end
        @cache[cache_key]
      end

      def mode
        @options[:mode]
      end

      private

      # Returns a suitable module for doing file operations
      #
      # @return [Module]
      def fileutils
        case @mode
        when :dryrun  then FileUtils::DryRun
        when :nowrite then FileUtils::NoWrite
        when :verbose then FileUtils::Verbose
        else               FileUtils
        end
      end

      # Returns whether the registry actually performs file operations or just simulates them
      #
      # @return [true|false]
      def noop?
        @mode == :dryrun || @mode == :nowrite
      end

      # Returns whether the registry should write file operations to the console
      #
      # @return [true|false]
      def verbose?
        @mode == :dryrun || @mode == :verbose
      end
    end
  end
end
