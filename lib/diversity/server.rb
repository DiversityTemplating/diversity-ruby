require 'pp'
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
      options = @options # To use options inside class_eval
      require 'sinatra/base'
      application = Class.new(Sinatra::Base)
      application.class_eval do
        helpers Sinatra::DiversityHelper
        # If we are running a local registry, make sure we expose files from
        # the registry in a consistent way
        if options[:registry].is_a?(Diversity::Registry::Local)
          get '/components/*' do
            path = File.join(options[:registry].base_path, params['splat'].first)
            if File.exist?(path)
              send_file(path)
            else
              halt 404
            end
          end
        end
        get '*' do
          canonical_url = get_canonical_url(request.env, options[:environment])

          # Work around bug in API that incorrectly forces us to specify protocol
          url_info = get_url_info(options[:backend], 'http://' + canonical_url)
          #url_info = get_url_info(options[:backend], canonical_url)

          backend_url_without_scheme =
            Addressable::URI.parse(options[:backend][:url])
          backend_url_without_scheme.scheme = nil
          backend_url_without_scheme = backend_url_without_scheme.to_s[2..-1]

          context = {
            backend_url: backend_url_without_scheme,
            webshop_uid: url_info[:webshop],
            webshop_url: 'http://' + Addressable::URI.parse('http://' + canonical_url).host
          }

          # For now, we use the same settings for all requests
          settings =
            Diversity::JsonSchemaCache[options[:configuration][:settings][:source]]

          # Render the main component
          options[:engine].render(options[:main_component], context, settings)
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
      if config.key?(:main_component) && config[:main_component].is_a?(Hash)
        mc_name =    config[:main_component][:name].to_s if
                       config[:main_component].key?(:name)
        mc_version = config[:main_component][:version].to_s if
                       config[:main_component].key?(:version)
      end
      mc_name ||= 'tws-theme'
      mc_version ||= '*'
      main_component = @options[:registry].get_component(mc_name, mc_version)
      fail Diversity::Exception, 'Cannot load main component ' \
           "#{mc_name} (#{mc_version})" unless
        main_component.is_a?(Diversity::Component)
    end
  end

end

# Helper methods used by the Diversity application
module Sinatra
  module DiversityHelper
    def get_canonical_url(request_env, app_env)
      host = request_env['HTTP_HOST']
      if app_env.key?(:host)
        host =
          case app_env[:host][:type]
          when 'regexp'
            host.gsub(Regexp.new(app_env[:host][:pattern]), '\1')
          when 'string'
            app_env[:host][:name]
          else
            host # Leave host as-is
          end
      end
      path = request_env['REQUEST_PATH'].empty? ?
             '/' : request_env['REQUEST_PATH']
      "#{host}#{path}"
    end

    def get_url_info(backend, page)
      data = {
        jsonrpc: '2.0',
        method: 'Url.get',
        params: [page, true],
        id: 1
      }
      result = Unirest.post(backend[:url], parameters: data.to_json)
      JSON.parse(result.raw_body, symbolize_names: true)[:result]
    end
  end
end
