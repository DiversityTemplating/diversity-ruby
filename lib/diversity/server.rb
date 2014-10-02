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
      pp @options
      ARGV.clear

      require 'sinatra/base'
      application = Class.new(Sinatra::Base)
      application.class_eval do
        get '/' do
          'craxy'
        end
      end

      #require_relative 'application'
      application.run!(@options[:configuration][:server] || {})

    end
    
    private
    
    def check_ruby_version
      if RUBY_VERSION.split('.').first.to_i != 2
        fail 'Server will only ruby on ruby version 2. ' \
             "You are running version #{RUBY_VERSION}.",
             Diversity::Exception, caller unless
          RUBY_VERSION.split('.').first.to_i == 2
      end
    end

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
      path = env['REQUEST_PATH'].empty? ? '/' : env['REQUEST_PATH']
      "#{host}#{path}"
    end

    def get_registry(config)
      fail 'Configuration does not specify a registry type.',
           Diversity::Exception, caller unless
        config.key?(:type)
      begin
        registry_class =
          Diversity::Registry.const_get(config[:type])
      rescue NameError
        fail 'Configuration specifies invalid registry type ' \
             "#{config[:type]}.", Diversity::Exception, caller
      end
      registry_class.new(config[:options] || {})
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
    
    def load_required_gems
      begin
        gem 'sinatra'
      rescue LoadError
        fail 'Failed to load sinatra. ' \
             'Please install sinatra before continuing.',
             Diversity::Exception, caller
      end
      begin
        gem 'unirest'
      rescue LoadError
        fail 'Failed to load unirest. ' \
             'Please install unirest before continuing.',
             Diversity::Exception, caller
      end
    end
    
    def load_configuration_file(file)
      fail "Configuration file #{file} is not readable.",
           Diversity::Exception, caller unless
        File.exist?(file) && File.readable?(file)
      require 'json'
      begin
        @options[:configuration] =
          JSON.parse(File.read(file), symbolize_names: true)
      rescue
        fail "Failed to parse configuration file #{file}. " \
             'It does not contain valid JSON.',
             Diversity::Exception, caller
      end
    end
    
    def parse_configuration
      config = @options[:configuration]
      @options[:backend] = config[:backend] || nil
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
      fail "Cannot load main component #{mc_name} (#{mc_version})" unless
        main_component.is_a?(Diversity::Component)
    end
  end

end
