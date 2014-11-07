require 'addressable/uri'
require 'fileutils'
require 'moneta'
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
        cache_options: { expires: 60, max_count: 100 },
        skip_validation: false
      }

      GLOB = '*/*/diversity.json'

      # Constructor
      #
      # @param [String] base_path
      # @param [Hash] options
      # @return Diversity::Registry::Local
      def initialize(options = {})
        @options = DEFAULT_OPTIONS.merge(options)
        @options[:base_path] = File.expand_path(@options[:base_path])
        fileutils.mkdir_p(@options[:base_path]) unless File.exist?(@options[:base_path])
        @cache = Moneta.build do
          use :Expires, expires: @options[:cache_options][:expires]
          adapter :LRUHash, max_count: @options[:cache_options][:max_count]
        end
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
              Gem::Requirement.create(version)

            # Get a list of versions.
            versions = Dir.glob('*')

            # Select highest matching version.
            version_path = versions.
              select {|version_path| requirement.satisfied_by?(Gem::Version.new(version_path)) }.
              sort.last.to_s

            puts "Selected #{version_path} out of #{versions.to_json}.\n"

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

          Component.new(self, spec, options)
        end
      end

      # Returns installed components matching the name and version of parameters
      #
      # @param [String] name
      # @param [nil|Gem::Requirement|Gem::Version|String] version
      # @return [Array]
      def get_matching_components(name, version = nil)
        if version.nil? # All versions
          finder = ->(comp) { comp.name == name }
        elsif version.is_a?(Gem::Requirement)
          finder = ->(comp) { comp.name == name && version.satisfied_by?(comp.version) }
        elsif version.is_a?(Gem::Version)
          finder = ->(comp) { comp.name == name && comp.version == version }
        elsif version.is_a?(String)
          req = Gem::Requirement.new(normalize_requirement(version))
          finder = ->(comp) { comp.name == name && req.satisfied_by?(comp.version) }
        else
          fail Diversity::Exception, "Invalid version #{version}", caller
        end

        # Find all matching components and sort them by their version (in descending order)
        installed_components.select(&finder).sort
      end

      # Returns a list of locally installed components
      #
      # @return [Array] An array of Component objects
      def installed_components
        return self.class.installed_components[@options[:base_path]] if
          self.class.installed_components.key?(@options[:base_path])
        Dir.chdir(@options[:base_path]) do
          self.class.installed_components[@options[:base_path]] =
            Dir.glob(GLOB).reduce([]) do |res, cfg|

            begin
              src = File.expand_path(cfg)
              spec = File.read(src)
              #src = File.expand_path(cfg)

              component = Component.new(
                self, spec, {
                  base_url: @options[:base_url] ?
                    @options[:base_url] + '/' + File.dirname(cfg) : nil,
                  base_path: File.dirname(src),
                  #skip_validation: true,
                }
              )
              res << component if res
            rescue Diversity::Exception => e
              puts "Caught an exception trying to put #{cfg} in list of installed components."
              p e
            end
            res
          end
        end
        self.class.installed_components[@options[:base_path]]
      end

      # Installs a component locally. If the component is already installed, it will not be
      # installed again unless the force flag is set to true
      #
      # @param [String] res components resource. Can be a path in the file system or an URL
      # @param [bool] force Whether component installation should be forced or not
      # @return [Diversity::Component]
      def install_component(res, force = false)
        comp = Component.new(self, res) # No base_uri here
        name = comp.name
        version = comp.version
        # If component is already installed, return locally
        # installed component instead (unless forced)
        return get_component(name, version) unless
          force || !installed?(name, version)
        # TODO: Make sure comp.name is a usable name
        res_path = remote?(res) ? uri_base_path(res) : File.dirname(File.expand_path(res))
        install_path = File.join(@options[:base_path], name, version.to_s)
        fileutils.mkdir_p(install_path)
        config_path = File.join(install_path, 'diversity.json')
        write_file(config_path, comp.dump, comp.src)
        copy_component_files(comp, res_path, install_path)
        # Invalidate cache (unless we are faking the installation)
        self.class.installed_components.delete(@options[:base_path]) unless noop?
        noop? ? comp : load_component(config_path)
      end

      def mode
        @options[:mode]
      end

      # Removes a locally installed component from the file system
      #
      # @param [String] name Component name
      # @param [Gem::Version|String|nil] version
      # @return [Array] An array of the versions that were removed
      def uninstall_component(name, version = nil)
        uninstalled_versions = []
        get_matching_components(name, version).each do |comp|
          uninstalled_versions << comp.version
          fileutils.rm_rf(comp.base_path) #fixme
        end
        # Invalidate cache (unless we are faking the uninstallation)
        self.class.installed_components.delete(@options[:base_path]) unless noop?
        uninstalled_versions
      end

      private

      def self.installed_components
        @installed_components ||= {}
      end

      def copy_component_files(component, src, dst)
        copy_files(component.templates, src, dst)
        copy_files(component.styles, src, dst) if component.styles
        copy_files(component.scripts, src, dst)
        # TODO: partials?
        copy_files(component.themes, src, dst)
        copy_files(component.thumbnail, src, dst) if component.thumbnail
        copy_files(
          component.settings.source, src, dst
        ) if component.settings.source && !remote?(component.settings.source)
        # TODO: assets?
      end

      # Copies a list of files
      #
      # @param [Array] files
      # @param [String] src_base_dir
      # @param [String] dst_base_dir
      # @return [nil]
      def copy_files(files, src_base_dir, dst_base_dir)
        files = [files] unless files.respond_to?(:each)
        files.each do |f|
          next if remote?(f)
          full_src = File.join(src_base_dir, f)
          full_dst = File.join(dst_base_dir, f)
          fail Diversity::Exception,
               "Failed to copy #{full_src} to #{full_dst}",
               caller unless (data = safe_load(full_src))
          dirname = File.dirname(full_dst)
          fileutils.mkdir_p(dirname) unless File.exist?(dirname) && File.directory?(dirname)
          write_file(full_dst, data, full_src)
        end
      end

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

      # Maybe writes a file and maybe tells the world about it
      #
      # @param [String] dst
      # @param [String] data
      # @param [String|nil] src
      # @return [nil]
      def write_file(dst, data, src = nil)
        puts(src ? "cp #{src} #{dst}" : "install #{dst}") if verbose?
        File.write(dst, data) unless noop?
        nil
      end
    end
  end
end
