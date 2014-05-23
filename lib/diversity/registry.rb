require 'fileutils'
require 'addressable/uri'
require_relative 'common'
require_relative 'component'
require_relative 'exception'

module Diversity
  # Class representing a list of locally install Component objects
  class Registry
    include Common

    # Glob representing locally installed component configurations
    GLOB = '*/*/diversity.json'

    attr_reader :base_path, :mode

    # Constructor
    #
    # @param [String] base_path
    # @param [Hash] options
    # @return Diversity::Registry
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
      # If component is already installed, return locally
      # installed component instead (unless forced)
      return get_component(comp.name, comp.version) unless
        force || !component_locally_installed?(comp.name, comp.version)
      # TODO: Make sure comp.name is a usable name
      res_path = remote?(res) ? uri_base_path(res) : File.dirname(File.expand_path(res))
      install_path = File.join(@base_path, comp.name, comp.version.to_s)
      fileutils.mkdir_p(install_path)
      write_file(File.join(install_path, 'diversity.json'), comp.dump, comp.src)
      copy_component_files(comp, res_path, install_path)
      # Invalidate cache (unless we are faking the installation)
      self.class.installed_components.delete(@base_path) unless noop?
      noop? ? comp : load_component(File.join(install_path, 'diversity.json'))
    end

    # Returns a locally installed version (or nil if the component does not exist).
    #
    # @param [String] name Component name
    # @param [String|Gem::Version] version Component version. If set to a Gem::Version, only the
    #   exact version is set for. If set to a string it is possible to search for a "fuzzy"
    #   version.
    # @return [Component|nil]
    def get_component(name, version = nil)
      get_matching_components(name, version).first
    end

    # Checks whether a component is installed locally.
    #
    # @param [String] name Component name
    # @param [String|Gem::Version|Gem::Requirement] version Component version. If set to a
    #   Gem::Version, only the exact version is set for. If set to a string or a Gem::Requirement
    #   it is possible to search for a "fuzzy" version.
    # @return [true|false]
    def component_locally_installed?(name, version = nil)
      get_matching_components(name, version).length > 0
    end

    # Loads a remote component
    #
    # @return [Component]
    def load_component(res)
      Component.new(res)
    end

    # Takes a list of components, loads all of their dependencies and returns a combined list of
    # components. Dependencies will only be included once.
    #
    # @param [Array] components An array of components
    # @return [Array] An expanded array of components
    def expand_component_list(*components)
      components.flatten!
      dependencies = []
      components.each do |component|
        component.dependencies.each_pair do |name, req|
          if req.is_a?(Addressable::URI) || req.is_a?(URI)
            component = load_component(req.to_s)
          elsif req.is_a?(Gem::Requirement)
            component = get_component(name, req)
          else
            fail Diversity::Exception, "Invalid dependency #{dependency}", caller
          end
          fail Diversity::Exception,
               "Failed to load dependency #{name} [#{req}]",
               caller unless component
          dependencies.concat expand_component_list(component) unless dependencies.any? do |d|
            component.name == d.name && component.version == d.version
          end || components.any? do |c|
            component.name == c.name && component.version == c.version
          end
        end
      end
      (dependencies << components).flatten
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
        component.options_src, src, dst
      ) if component.options_src && !remote?(component.options_src)
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
      when :dryrun
        FileUtils::DryRun
      when :nowrite
        FileUtils::NoWrite
      when :verbose
        FileUtils::Verbose
      else
        FileUtils
      end
    end

    # Returns locally installed components matching the name and version of parameters
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
      installed_components.select(&finder).sort { |a, b| b.version <=> a.version }
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
