require 'logger'
require_relative 'exception.rb'

module Diversity
  class Server
    def initialize(options = {})
      @options = options
      begin
        check_ruby_version
        load_required_gems
        load_configuration_file(@options[:configuration_file])
        parse_configuration
      rescue Diversity::Exception => err
        puts err.message
        exit 1
      end
    end

    def run
      build_application.run!(@options[:configuration][:server] || {})
    end

    private

    def build_application
      opts = @options # To use @options inside class_eval
      if opts.key?(:logging)
        access_logger = opts[:logging].key?(:access) ?
                        opts[:logging][:access] : nil
        error_logger  = opts[:logging].key?(:error) ?
                        opts[:logging][:error] : nil
      end
      require 'sinatra/base'
      application = Class.new(Sinatra::Base)
      application.class_eval do
        @options = opts
        def options; self.class.instance_variable_get(:@options); end
        helpers Sinatra::DiversityHelper
        # Set up access logging if requested
        configure { use ::Rack::CommonLogger, access_logger } if access_logger
        # Set up error logging if requested
        before { env["rack.errors"] =  error_logger } if error_logger
        # If we are running a local registry, make sure we expose files from
        # the registry in a consistent way
        if opts[:registry].is_a?(Diversity::Registry::Local)
          get '/components/*' do
            path = File.join(opts[:registry].base_path, params['splat'].first)
            if File.exist?(path)
              send_file(path)
            else
              halt 404
            end
          end
        end
        get '*' do
          canonical_url = get_canonical_url(request)
          # Work around bug in API that incorrectly forces us to specify protocol
          url_info = call_api('Url.get', ['http://' + canonical_url, true])
          #url_info = get_url_info(opts[:backend], canonical_url)

          backend_url_without_scheme =
            Addressable::URI.parse(opts[:backend][:url])
          backend_url_without_scheme.scheme = nil
          backend_url_without_scheme = backend_url_without_scheme.to_s[2..-1]

          context = {
            backend_url: backend_url_without_scheme,
            webshop_uid: url_info['webshop'],
            webshop_url: 'http://' + Addressable::URI.parse('http://' + canonical_url).host
          }

          main_component, settings =
            get_main_component_with_settings(request, {webshop: url_info['webshop']})

          # settings = Diversity::JsonSchemaCache[opts[:configuration][:settings][:source]]

          # Render the main component
          opts[:engine].render(main_component, context, settings)
        end
      end
      application
    end

    def check_ruby_version
      if RUBY_VERSION.split('.').first.to_i != 2
        fail Diversity::Exception,
             'Server will only ruby on ruby version 2. ' \
             "You are running version #{RUBY_VERSION}.", caller unless
          RUBY_VERSION.split('.').first.to_i == 2
      end
    end

    def get_registry(config)
      fail Diversity::Exception,
           'Configuration does not specify a registry type.',
           caller unless config.key?(:type)
      begin
        registry_class =
          Diversity::Registry.const_get(config[:type])
      rescue NameError
        fail Diversity::Exception,
             'Configuration specifies invalid registry type ' \
             "#{config[:type]}.", caller
      end
      registry_class.new(config[:options] || {})
    end

    def load_required_gems
      begin
        gem 'sinatra'
      rescue LoadError
        fail Diversity::Exception, 'Failed to load sinatra. ' \
             'Please install sinatra before continuing.', caller
      end
      begin
        gem 'unirest'
      rescue LoadError
        fail Diversity::Exception, 'Failed to load unirest. ' \
             'Please install unirest before continuing.', caller
      end
    end

    def load_configuration_file(file)
      fail Diversity::Exception,
          "Configuration file #{file} is not readable.", caller unless
        File.exist?(file) && File.readable?(file)
      require 'json'
      begin
        @options[:configuration] =
          JSON.parse(File.read(file), symbolize_names: true)
      rescue
        fail Diversity::Exception,
             "Failed to parse configuration file #{file}. " \
             'It does not contain valid JSON.', caller
      end
    end

    def parse_configuration
      config = @options[:configuration]
      @options[:backend] = config[:backend] || nil
      @options[:environment] = config[:environment] || {}
      require_relative '../diversity.rb'
      @options[:registry] = get_registry(config[:registry] || {})
      engine_options = { registry: @options[:registry] }
      # If we are using a local repository, expose component files
      if @options[:registry].is_a?(Diversity::Registry::Local)
        engine_options[:public_path] = '/components'
      end
      @options[:engine] = Diversity::Engine.new(engine_options)
      # Check if the configuration contains information about what to use
      # as a "main component"
      @options[:main_component] = {}
      if config.key?(:main_component) && config[:main_component].is_a?(Hash)
        @options[:main_component][:name] =
          config[:main_component][:name] || 'tws-theme'
        @options[:main_component][:version] =
          config[:main_component][:version] || '*'
      else
        @options[:main_component][:name] = 'tws-theme'
        @options[:main_component][:version] = '*'
      end
      if config.key?(:settings) && config[:settings].is_a?(Hash) &&
         config[:settings].key?(:source)
        @options[:settings] =
          JSON.parse(File.read(config[:settings][:source]))
      else
        @options[:settings] = {}
      end
      if config.key?(:logging)
        ::Logger.class_eval { alias :write :'<<' }
        @options[:logging] = {}
        if config[:logging].key?(:access)
          @options[:logging][:access] =
            ::Logger.new(::File.expand_path(config[:logging][:access]))
        end
        if config[:logging].key?(:error)
          @options[:logging][:error] =
            ::File.new(::File.expand_path(config[:logging][:error]), 'a+')
          @options[:logging][:error].sync = true
        end
      end
    end
  end

end

# Helper methods used by the Diversity application
module Sinatra
  module DiversityHelper
    def call_api(meth, params, context = {})
      payload = {
        jsonrpc: '2.0',
        method: meth,
        params: params,
        id: 1
      }
      backend_url = Addressable::URI.parse(options[:backend][:url])
      backend_context = context.merge(backend_url.query_values || {})
      backend_url.query_values = backend_context unless
        backend_context.empty?
      result = Unirest.post(backend_url.to_s, parameters: payload.to_json)
      JSON.parse(result.raw_body)['result']

    end

    def get_canonical_url(request)
      host = request.env['HTTP_HOST']
      if options[:environment].key?(:host)
        host =
          case options[:environment][:host][:type]
          when 'regexp'
            host.gsub(Regexp.new(options[:environment][:host][:pattern]), '\1')
          when 'string'
            options[:environment][:host][:name]
          else
            host # Leave host as-is
          end
      end
      path = request.env['REQUEST_PATH'].empty? ?
             '/' : request.env['REQUEST_PATH']
      "#{host}#{path}"
    end

    def get_main_component_with_settings(request, context)
      if request.cookies.key?('tid')
        # Theme information available from request
        component_id = request.cookies['tid'].to_i
        component_info =
          call_api('Theme.get', [component_id, true], context)
        component_name = component_info['params']['layout'] || 'tws-theme'
        component_version = component_info['params']['version'] || '*'
        component_settings = component_info['params']['settings'] || {}
      else
        component_name = options[:main_component][:name]
        component_version = options[:main_component][:version]
        component_settings = options[:settings]
      end
      component =
        options[:registry].get_component(component_name, component_version)
      fail Diversity::Exception, 'Cannot load main component ' \
           "#{component_name} (#{component_version})" unless
        component.is_a?(Diversity::Component)
      [component, Diversity::JsonObject[component_settings]]
    end
  end
end
