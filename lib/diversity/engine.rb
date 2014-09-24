require 'mustache'

module Diversity
  # Class for rendering Diversity components
  class Engine
    include Common

    # A simple wrapper for the context used when rendering
    class Settings
      ivars = [:angular, :scripts, :styles]
      define_method :initialize do
        ivars.each do |ivar|
          instance_variable_set "@#{ivar}".to_sym, []
        end
      end
      ivars.each do |ivar|
        ivar_ref = "@#{ivar}".to_sym
        define_method "add_#{ivar}".to_sym do |values|
          values.each do |value|
            next unless value # No nils or falsies allowed!
            ivar_obj = instance_variable_get(ivar_ref)
            ivar_obj << value unless ivar_obj.include?(value)
          end
        end
        define_method ivar do
          instance_variable_get(ivar_ref)
        end
      end
    end

    @settings = {}

    # Default options for engine
    DEFAULT_OPTIONS = {
      backend_url: nil, # Optional, might be overridden in render
      minify_js: false,
      public_path: nil,
      public_path_proc: nil,
      registry: nil
    }

    def initialize(options = {})
      @options = DEFAULT_OPTIONS.merge(options)
      # Ensure that we have a valid registry to work against
      fail 'Cannot run engine without a valid registry!' unless @options[:registry].is_a?(Registry::Base)
    end

    # Renders a component
    # @param [Diversity::Component] component
    # @param [Diversity::JsonObject] json_settings
    # @param [Array] key
    # @return [Hash|String]
    def render(component, context = {}, json_settings = JsonObject.new({}), key = [])
      # Some basic validation that protects us from rendering stuff we
      # cannot handle
      fail 'First argument must be a Diversity::Component, but you sent ' \
           " a #{component.class}" unless component.is_a?(Component)
      fail 'Third argument must be a Diversity::JsonObject, but you sent ' \
           "a #{json_settings.class}" unless json_settings.is_a?(JsonObject)
      validate_settings(component.settings, json_settings)

      # Step 1 - Load components that we depend on
      components = @options[:registry].expand_component_list(component)
      update_settings(components)

      # 3. Extract subcomponents from the settings
      # 4. Make sure that all components are available
      # 5. Iterate through the list of components (from the "innermost") and render them

      # all_templatedata represents *all* templatedata gathered so far
      # After the following loop it will contain the template data of
      # all *subcomponents* of the current components
      all_templatedata = {}
      get_subcomponents(component, json_settings).each do |sub|
        sub_key = sub[2]
        all_templatedata[sub_key] ||= []
        all_templatedata[sub_key] << render(sub[0], context, sub[1], sub_key)[sub_key]
      end

      # Components might contain more than one subcomponent. In that case,
      # make sure that we merge all rendered HTML into a single element
      all_templatedata = self.class.merge_contents(all_templatedata)

      # current_templatedata represents the templatedata for the *current*
      # component. Since the rendering of the current component is esentially
      # wrapping up the HTML of all subcomponents we build this structure
      # from all the previously rendered components.
      current_templatedata = {}
      all_templatedata.each_pair do |hkey, hvalue|
        new_key = (hkey.dup) << 'componentHTML'
        node = [new_key, hvalue]
        current_templatedata = current_templatedata.keep_merge(node_to_hash(node))
      end

      # Merge current_templatedata with the current settings
      settings_hash = {}
      if key.empty?
        settings_hash[:settings] = current_templatedata
      else
        settings_hash[:settings] = json_settings.data.keep_merge(current_templatedata)
      end
      # According to David we need the settings as JSON as well
      settings_hash[:settingsJSON] =
        settings_hash[:settings].to_json.gsub(/<\/script>/i, '<\\/script>')
      if key.empty? # TOP LEVEL, we need to render scripts and styles
        settings_hash['angularBootstrap'] =
          "angular.bootstrap(document,#{settings.angular.to_json});"
        settings_hash['scripts'] = settings.scripts
        settings_hash['styles'] = settings.styles
      end

      templates = component.templates.map do |template|
        expand_component_paths(component.base_path, template)
      end

      all_templates = []
      templates.each do |template|
        all_templates << render_template(component, template, context, settings_hash)
      end
      all_templatedata[key] = all_templates.join('')

      if key.empty?
        delete_settings
        all_templatedata[key]
      else
        all_templatedata
      end
    end

    private

    # Returns the default rendering context for the current engine
    #
    # @return [Hash]
    def settings
      self.class.settings[self] ||= Settings.new
    end

    # Deletes the rendering context for the current engine
    def delete_settings
      self.class.settings.delete(self)
    end

    def public_path(component)
      # If the user has provided a Proc for the public path, call it
      proc = @options[:public_path_proc]
      return proc.call(self, component) if proc
      # If the user has provided a String for the public path, use that
      path = @options[:public_path]
      return File.join(path, component.name, component.version.to_s) if path
      # Use the component's base path by default
      File.join(component.base_path, component.name, component.version.to_s)
    end

    # Update the rendering context with data from the currently
    # rendering component.
    #
    # @param [Array] An array of Diversity::Component objects
    # @return [nil]
    def update_settings(components)
      components.each do |component|
        component_path = public_path(component)
        settings.add_angular([component.angular].flatten)
        settings.add_scripts(
          expand_component_paths(component_path, component.scripts)
        )
        settings.add_styles(
          expand_component_paths(component_path, component.styles)
        )
      end
      nil
    end

    class << self
      attr_reader :settings
    end

    # Merges all content in a single key to a single string.
    #
    # @param [Hash] contents
    # @return [Hash]
    def self.merge_contents(contents)
      contents.each_with_object({}) do |(key, value), hsh|
        hsh[key] = value.join('')
      end
    end

    # Make sure that the provided settings are valid
    def validate_settings(available_settings, requested_settings)
      begin
        available_settings.validate(requested_settings)
      rescue
        # failed to validate settings. now what?
        puts 'Oops, failed to validate settings'
      end
    end

    # Returns an array of possible subcomponents for the specified component
    #
    # @param [Diversity::Component] component
    # @param [Diversity::JsonObject] settings
    # @return [Array]
    def get_subcomponents(component, settings)
      subcomponents = []
      component_keys = component.settings.select do |node|
        last = node.last
        last['type'] == 'object' && last['format'] == 'diversity'
      end
      return [] if component_keys.empty?
      component_keys.map!(&:first)
      new_keys = []
      component_keys.each do |key|
        new_keys << key.reject { |elem| elem == 'properties' || elem == 'items' }
      end
      # Sort by key length first and then by each key
      klass = self.class
      new_keys = new_keys.sort do |one_obj, another_obj|
        klass.sort_by_key(one_obj, another_obj)
      end
      new_keys.each do |key|
        components = klass.extract_setting(key, settings)
        next if components.nil?
        components.each do |c|
          comp = @options[:registry].get_component(c['component'])
          fail "Cannot load component #{c['component']}" if comp.nil?
          subcomponents << [comp, JsonObject[c['settings']], key]
        end
      end
      subcomponents
    end

    # Given a schema key, returns the setting associated with that key
    # @param [Array] key
    # @param [Diversity::JsonSchema] settings
    # @return [Array]
    def self.extract_setting(key, settings)
      new_key = key.dup
      last = new_key.pop
      data = settings[new_key]
      return [] unless data && !data.empty?
      setting = data[last]
      return [] unless setting && !setting.empty?
      [setting].flatten # Always return an array
    end

    # Create a list of absolute paths from a base path and a list of
    # relative paths.
    #
    # @param [String] base_path
    # @param [Enumerable|String] file_list
    # @return [Array]
    def expand_component_paths(base_path, file_list)
      return nil if file_list.nil?
      if file_list.respond_to?(:each)
        file_list.map do |file|
          res = file.to_s
          remote?(res) ? res : File.join(base_path, res)
        end
      else
        f = file_list.to_s
        return file_list if f.empty?
        remote?(f) ? f : File.join(base_path, f)
      end
    end

    # Given a component, a mustache template and some settings, return
    # a rendered HTML string.
    #
    # @param [Diversity::Component] component
    # @param [String] template
    # @param [Hash] settings
    # @return [String]
    def render_template(component, template, context, settings)
      template_data = safe_load(template)
      return nil unless template_data # No need to render empty templates
      # Add data from API
      rcontext = component.resolve_context(context[:backend_url], context)
      rcontext = settings.keep_merge({context: rcontext})
      # Add some tasty Mustache lambdas
      rcontext['currency'] =
        lambda do |text, render|
          # TODO: Fix currency until we decide how to it
          text.gsub(/currency/, 'SEK')
        end
      rcontext['gettext'] =
        lambda do |text|
          # TODO: Maybe, maybe not, But later anyway
          text
        end
      rcontext['lang'] = lambda do |text|
        # TODO: Fix language until we decide how to set it
        text.gsub(/lang/, 'sv')
      end
      # Return rendered data
      Mustache.render(template_data, rcontext)
    end

    # Compares two nodes by key_length and then key-by-key
    #
    # @param [Array] one_obj
    # @param [Array] another_obj
    # @return [Fixnum]
    def self.sort_by_key(one_obj, another_obj)
      len_cmp = another_obj.length  <=> one_obj.length
      return len_cmp if len_cmp.nonzero?
      one_obj.each_with_index do |key, index|
        key_cmp = another_obj[index] <=> key
        return key_cmp if key_cmp.nonzero?
      end
      0
    end

    # Converts a "node" array to a regular hash
    #
    # @param [Array] node
    # @return [Hash]
    def node_to_hash(node)
      key, value = node
      fail 'Empty key not allowed' if key.empty?
      current_hash = {}
      outermost_hash = current_hash
      key.each_with_index do |elem, index|
        if index < key.length - 1
          current_hash[elem] = {}
          current_hash = current_hash[elem]
        else
          current_hash[elem] = value
        end
      end
      outermost_hash
    end
  end
end
