module Diversity
  # Diversity rendering engine
  class Engine
    # A simple wrapper for the context used when rendering
    class Settings
      include Common

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
        fail 'Must have a base dir' unless options[:base_dir]
        fail 'Must have a base url' unless options[:base_url]
        options[:filename] = random_name unless options[:filename]
        require 'set'
        scripts_to_minify = Set.new
        scripts = Set.new
        path = File.expand_path(
                 File.join(options[:base_dir], 'scripts', "#{options[:filename]}.min.js")
               )
        minified_exist = File.exist?(path)

        # Calculate list of script to minify
        @component_set.to_a.each do |component|
          component.scripts.each do |script|
            if !remote?(script) || options[:minify_remotes]
              next if minified_exist
              scripts_to_minify << script
            else
              scripts << script
            end
          end
        end

        scripts = scripts.to_a

        # Load scripts and minify them
        unless scripts_to_minify.empty?
          minified_data = parallell_load(scripts_to_minify)
          unless minified_data.empty?
            require 'uglifier'
            uglifier = Uglifier.new
            minified = ''
            minified_data.each_value do |val|
              minified << uglifier.compile(val << "\n")
            end
          end
          create_minified_file(path, minified) unless minified_exist || minified.empty?
          scripts.unshift(minified_url(options[:base_url], path)) if
            minified_exist || !minified.empty?
        end

        scripts
      end

      def minified_styles(options)
        fail 'Must have a base dir' unless options[:base_dir]
        fail 'Must have a base url' unless options[:base_url]
        options[:filename] = random_name unless options[:filename]
        require 'set'
        styles_to_minify = Set.new
        styles = Set.new
        path = File.expand_path(
                 File.join(options[:base_dir], 'styles', "#{options[:filename]}.min.css")
               )
        minified_exist = File.exist?(path)

        # Calculate list of styles to minify
        @component_set.to_a.each do |component|
          component.styles.each do |style|
            if !remote?(style) || options[:minify_remotes]
              next if minified_exist
              styles_to_minify << style
            else
              styles << style
            end
          end
        end

        styles = styles.to_a

        # Load styles and minify them
        unless styles_to_minify.empty?
          minified_data = parallell_load(styles_to_minify)
          unless minified_data.empty?
            require 'cssminify'
            compressor = CSSminify.new
            minified = ''
            minified_data.each_value do |val|
              minified << compressor.compress(val << "\n")
            end
          end
          create_minified_file(path, minified) unless minified_exist || minified.empty?
          styles.unshift(minified_url(options[:base_url], path)) if
            minified_exist || !minified.empty?
        end

        styles
      end

      def scripts
        @component_set.to_a.map(&:scripts).flatten.uniq
      end

      def styles
        @component_set.to_a.map(&:styles).flatten.uniq
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
