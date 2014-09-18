require 'mustache'
require 'set'

module Diversity
  # Class for rendering Diversity components
  class Engine
    include Common

    @rendering_context = {}

    # Default options for engine
    DEFAULT_OPTIONS = {
      backend_url: nil,
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
    # @param [Diversity::JsonObject] settings
    # @param [Array] key
    # @return [Hash|String]
    def render(component, settings, key = [])
      # Some basic validation that protects us from rendering stuff we
      # cannot handle
      fail 'First argument must be a Diversity::Component, but you sent ' \
           " a #{component.class}" unless component.is_a?(Component)
      fail 'Second argument must be a Diversity::JsonObject, but you sent ' \
           "a #{settings.class}" unless settings.is_a?(JsonObject)
      validate_settings(component.settings, settings)

      # Step 1 - Load components that we depend on
      components = @options[:registry].expand_component_list(component)
      update_context(components)

      # 3. Extract subcomponents from the settings
      # 4. Make sure that all components are available
      # 5. Iterate through the list of components (from the "innermost") and render them

      # all_templatedata represents *all* templatedata gathered so far
      # After the following loop it will contain the template data of
      # all *subcomponents* of the current components
      all_templatedata = {}
      get_subcomponents(component, settings).each do |sub|
        sub_key = sub[2]
        all_templatedata[sub_key] ||= []
        all_templatedata[sub_key] << render(sub[0], sub[1], sub_key)[sub_key]
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
      settings_hash[:settings] = settings.data.keep_merge(current_templatedata)
      # According to David we need the settings as JSON as well
      settings_hash[:settingsJSON] =
        settings_hash[:settings].to_json.gsub(/<\/script>/i, '<\\/script>')
      if key.empty? # TOP LEVEL, we need to render scripts and styles
        settings_hash['scripts'] = context[:scripts].to_a
        settings_hash['styles'] = context[:styles].to_a
      end

      templates = component.templates.map do |template|
        expand_component_paths(component.base_path, template)
      end

      all_templates = []
      templates.each do |template|
        all_templates << render_template(component, template, settings_hash)
      end
      all_templatedata[key] = all_templates.join('')

      if key.empty?
        delete_context
        all_templatedata[key]
      else
        all_templatedata
      end
    end

    private

    # Returns the default rendering context for the current engine
    #
    # @return [Hash]
    def context
      self.class.rendering_context[self] ||= { scripts: Set.new, styles: Set.new }
    end

    # Deletes the rendering context for the current engine
    def delete_context
      self.class.rendering_context.delete(self)
    end

    def public_path(component)
      # If the user has provided a Proc for the public path, call it
      proc = @options[:public_path_proc]
      return proc.call(self, component) if proc
      # If the user has provided a String for the public path, use that
      path = @options[:public_path]
      return path if path
      # Use the component's base path by default
      File.join(component.base_path, component.name, component.version.to_s)
    end

    # Update the rendering context with data from the currently
    # rendering component.
    #
    # @param [Array] An array of Diversity::Component objects
    # @return [nil]
    def update_context(components)
      components.each do |component|
        component_path = public_path(component)
        add_to_context_set(
          :scripts,
          expand_component_paths(component_path, component.scripts)
        )
        add_to_context_set(
          :styles,
          expand_component_paths(component_path, component.styles)
        )
      end
      nil
    end

    # Adds a value to a specific context unless the value is already
    # present in the key.
    #
    # @param [Symbol] key
    # @param [Array] values
    def add_to_context_set(key, values)
      values.each { |value| context[key].add(value) }
      nil
    end

    class << self
      attr_reader :rendering_context
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
    # @return [Array|nil]
    def self.extract_setting(key, settings)
      new_key = key.dup
      last = new_key.pop
      data = settings[new_key]
      return nil unless data && !data.empty?
      setting = data[last]
      return nil unless setting && !setting.empty?
      setting
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
    def render_template(component, template, settings)
      template_data = safe_load(template)
      return nil unless template_data # No need to render empty templates
      # Add data from API
      context = component.resolve_context(@options[:backend_url], component.context)
      settings = settings.keep_merge(context)
      # Return rendered data
      Mustache.render(template_data, settings)
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
