module Diversity
  # Diversity rendering engine
  class Engine
    # A simple wrapper for the context used when rendering
    class Settings
      include Common

      DEFAULT_MINIFY_OPTIONS = {
        base_dir: nil,
        base_url: nil,
        filename: nil,
        minify_remotes: false
      }

      def initialize(registry)
        @component_set = Diversity::ComponentSet.new(registry)
      end

      def add_component(component)
        @component_set << component
      end

      def angular
        @component_set.to_a.reduce([]) do |angular, comp|
          if comp.angular
            angular << comp.angular
          else
            angular
          end
        end
      end

      def l10n(langcode)
        @component_set.to_a.reduce([]) do |l10n, comp|
          if comp.i18n &&
             comp.i18n.key?(langcode) &&
             comp.i18n[langcode].key?('view') # i18n will be changed to l10n later
            if (data = comp.get_asset(comp.i18n[langcode]['view']))
              l10n << {
                'component' => comp.name,
                'messages'  => data
              }
            else
              # puts "Failed to load #{comp.i18n[langcode]['view']}"
              l10n
            end
          else
            l10n
          end
        end
      end

      def minified_scripts(options = {})
        opts = DEFAULT_MINIFY_OPTIONS.merge(options)
        fail 'Must have a base dir' unless opts[:base_dir]
        fail 'Must have a base url' unless opts[:base_url]
        opts[:filename] = random_name unless opts[:filename]
        scripts = []
        path = File.expand_path(File.join(opts[:base_dir], 'scripts', opts[:filename]))
        minified_exist = File.exist?(path)
        require 'uglifier'
        uglifier = Uglifier.new
        minified = ''
        @component_set.to_a.each do |component|
          component.scripts.each do |script|
            if !remote?(script) || opts[:minify_remotes]
              next if minified_exist
              data = safe_load(script)
              minified << uglifier.compile(data << "\n") if data
            else
              scripts << script
            end
          end
        end
        create_minified_file(path, minified) unless minified_exist || minified.empty?
        scripts.unshift(minified_url(opts[:base_url], path)) if minified_exist || !minified.empty?
        scripts
      end

      def minified_styles(options = {})
        opts = DEFAULT_MINIFY_OPTIONS.merge(options)
        fail 'Must have a base dir' unless opts[:base_dir]
        fail 'Must have a base url' unless opts[:base_url]
        opts[:filename] = random_name unless opts[:filename]
        styles = []
        path = File.expand_path(File.join(opts[:base_dir], 'styles', opts[:filename]))
        minified_exist = File.exist?(path)
        require 'cssminify'
        compressor = CSSminify.new
        minified = ''
        @component_set.to_a.each do |component|
          component.styles.each do |style|
            if !remote?(style) || opts[:minify_remotes]
              next if minified_exist
              data = safe_load(style)
              minified << compressor.compress(data << "\n") if data
            else
              styles << style
            end
          end
        end
        create_minified_file(path, minified) unless minified_exist || minified.empty?
        styles.unshift(minified_url(opts[:base_url], path)) if minified_exist || !minified.empty?
        styles
      end

      def scripts
        @component_set.to_a.map { |comp| comp.scripts }.flatten
      end

      def styles
        @component_set.to_a.map { |comp| comp.styles }.flatten
      end

      private

      # Writes minified data to file system.
      #
      # @param [String] path
      # @param [String] data
      # @return [String]
      def create_minified_file(path, data)
        require 'fileutils'
        path = File.expand_path(path)
        FileUtils.mkdir_p(File.dirname(path), mode: 0775)
        File.open(path, 'w') { |file| file.write(data) }
        path
      end

      # Returns an URL that can be used to access the specified minified content
      #
      # @param [String] base_url
      # @param [String] path
      # @return [String]
      def minified_url(base_url, path)
        url = base_url.dup
        url << '/' unless url[-1] == '/' # Adds trailing slash to base url if needed
        pt = File.expand_path(path)
        parts = pt.split(File::SEPARATOR).map { |p| p.empty? ? File::SEPARATOR : p }
        url << parts[-2] << '/' << parts[-1]
        url
      end

      # Generates a random filename
      #
      # @return [String]
      def random_name
        require 'securerandom'
        SecureRandom.urlsafe_base64
      end
    end
  end
end
