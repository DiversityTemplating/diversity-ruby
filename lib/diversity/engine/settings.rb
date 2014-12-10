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

        filename = options[:filename] || Digest::SHA1.hexdigest(scripts.join(';'))
        require 'set'
        minified_scripts = Set.new
        scripts = Set.new
        path = File.expand_path(
                 File.join(options[:base_dir], 'scripts', "#{filename}.min.js")
               )
        minified_exist = File.exist?(path)
        require 'uglifier'
        uglifier = Uglifier.new
        minified = ''
        @component_set.to_a.each do |component|
          component.scripts.each do |script|
            if !remote?(script) || options[:minify_remotes]
              next if minified_exist || minified_scripts.include?(script)
              data = safe_load(script)
              if data
                minified << uglifier.compile(data << "\n")
                minified_scripts << script
              else
                p "Failed to load #{script}"
              end
            else
              scripts << script
            end
          end
        end
        create_minified_file(path, minified) unless minified_exist || minified.empty?
        scripts = scripts.to_a
        scripts.unshift(
          minified_url(options[:base_url], path)
        ) if minified_exist || !minified.empty?
        scripts
      end

      def minified_styles(options)
        fail 'Must have a base dir' unless options[:base_dir]
        fail 'Must have a base url' unless options[:base_url]

        filename = options[:filename] || Digest::SHA1.hexdigest(styles.join(';'))
        require 'set'
        minified_styles = Set.new
        styles = Set.new
        path = File.expand_path(
                 File.join(options[:base_dir], 'styles', "#{filename}.min.css")
               )
        minified_exist = File.exist?(path)
        require 'cssminify'
        compressor = CSSminify.new
        minified = ''
        @component_set.to_a.each do |component|
          component.styles.each do |style|
            if !remote?(style) || options[:minify_remotes]
              next if minified_exist || minified_styles.include?(style)
              data = safe_load(style)
              if data
                minified << compressor.compress(data << "\n")
                minified_styles << style
              else
                p "Failed to load #{style}"
              end
            else
              styles << style
            end
          end
        end
        create_minified_file(path, minified) unless minified_exist || minified.empty?
        styles = styles.to_a
        styles.unshift(minified_url(options[:base_url], path)) if minified_exist || !minified.empty?
        styles
      end

      def scripts
        @component_set.to_a.map(&:scripts).flatten.uniq
      end

      def concatenated_scripts(options = {})
        fail 'Must have a base dir' unless options[:base_dir]

        filename = options[:filename] || Digest::SHA1.hexdigest(scripts.join(';'))
        path = File.expand_path(
          File.join(options[:base_dir], 'scripts', "#{filename}.concat.js")
        )
        return safe_load(path) if File.exist?(path)

        script_data = scripts.each.map {|script| "/* #{script} */\n#{safe_load(script)}"}.join("\n")
        create_minified_file(path, script_data)
        script_data
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
    end
  end
end
