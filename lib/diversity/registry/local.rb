require 'fileutils'
require 'addressable/uri'
require_relative '../common.rb'
require_relative '../component.rb'
require_relative '../exception.rb'

module Diversity
  module Registry
    # Class representing a list of locally installed Component objects
    class Local < Base
      # Glob representing locally installed component configurations
      GLOB = '*/*/diversity.json'

      attr_reader :base_path, :mode

      # Constructor
      #
      # @param [String] base_path
      # @param [Hash] options
      # @return Diversity::LocalRegistry
      def initialize(base_path, options = {})
        @base_path = File.expand_path(base_path)
        @mode = options.key?(:mode) ? options[:mode].to_sym : :default
        fileutils.mkdir_p(@base_path) unless File.exist?(@base_path)
      end

      # Returns a list of locally installed components
      #
      # @return [Array] An array of Component objects
      def installed_components
        return self.class.installed_components[@base_path] if
          self.class.installed_components.key?(@base_path)
        Dir.chdir(@base_path) do
          self.class.installed_components[@base_path] = Dir.glob(GLOB).reduce([]) do |res, cfg|
            res << Component.new(cfg, true) # No need to validate here
          end
        end
        self.class.installed_components[@base_path]
      end

      # Installs a component locally. If the component is already installed, it will not be
      # installed again unless the force flag is set to true
      #
      # @param [String] res components resource. Can be a path in the file system or an URL
      # @param [bool] force Whether component installation should be forced or not
      # @return [Diversity::Component]
      def install_component(res, force = false)
        comp = Component.new(res)
        name = comp.name
        version = comp.version
        # If component is already installed, return locally
        # installed component instead (unless forced)
        return get_component(name, version) unless
          force || !installed?(name, version)
        # TODO: Make sure comp.name is a usable name
        res_path = remote?(res) ? uri_base_path(res) : File.dirname(File.expand_path(res))
        install_path = File.join(@base_path, name, version.to_s)
        fileutils.mkdir_p(install_path)
        config_path = File.join(install_path, 'diversity.json')
        write_file(config_path, comp.dump, comp.src)
        copy_component_files(comp, res_path, install_path)
        # Invalidate cache (unless we are faking the installation)
        self.class.installed_components.delete(@base_path) unless noop?
        noop? ? comp : load_component(config_path)
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
          fileutils.rm_rf(comp.base_path)
        end
        # Invalidate cache (unless we are faking the uninstallation)
        self.class.installed_components.delete(@base_path) unless noop?
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