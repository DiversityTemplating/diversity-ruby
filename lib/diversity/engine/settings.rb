module Diversity
  # Diversity rendering engine
  class Engine
    # A simple wrapper for the context used when rendering
    class Settings
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

      def minified_scripts(base_dir, theme_id, theme_timestamp)
        path = File.expand_path(File.join(base_dir, 'scripts', "#{theme_id}-#{theme_timestamp.to_i}"))
        p "Minified script path: #{path}"
        return path if File.exist?(path)
        require 'yui/compressor'
        compressor = YUI::JavaScriptCompressor.new
        minified = ''
        @component_set.to_a.each do |component|
          component.scripts.each do |script|
            next if remote?(script)
            minified << compressor.compress(safe_load(script))
          end
        end
        create_minified_file(path, minified)
      end

      def minified_styles(base_dir, theme_id, theme_timestamp)
        path = File.expand_path(File.join(base_dir, 'scripts', "#{theme_id}-#{theme_timestamp.to_i}"))
        return path if File.exist?(path)
        require 'yui/compressor'
        compressor = YUI::CSSCompressor.new
        minified = ''
        @component_set.to_a.each do |component|
          component.styles.each do |style|
            next if remote?(style)
            minified << compressor.compress(safe_load(style))
          end
        end
        create_minified_file(path, minified)
      end

      def scripts
        @component_set.to_a.map { |comp| comp.scripts }.flatten
      end

      def styles
        @component_set.to_a.map { |comp| comp.styles }.flatten
      end

      private

      def create_minified_file(path, data)
        require 'fileutils'
        FileUtils.mkdir_p(File.dirname(path), mode: 0775)
        File.open(path, 'w') { |file| file.write(data) }
        path
      end
    end
  end
end
