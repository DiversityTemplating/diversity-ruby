require 'digest/sha2'
require 'cache'
require_relative 'exception.rb'
require_relative 'server/configuration.rb'

module Diversity
  class Server
    def initialize(options = {})
      begin
        check_ruby_version
        load_required_gems
        @configuration = Server::Configuration.new(options[:configuration_file])
      rescue Diversity::Exception => err
        puts err.message
        exit 1
      end
    end

    def run
      @configuration.server.dump_errors = false if
        @configuration.server.dump_errors.nil?
      @configuration.server.raise_errors = false if
        @configuration.server.raise_errors.nil?
      @configuration.server.show_exceptions = false if
        @configuration.server.show_exceptions.nil?
      build_application.run!(@configuration.server.to_h || {})
    end

    private

    def build_application
      config = @configuration # To use @configuration inside class_eval
      require 'sinatra/base'
      application = Class.new(Sinatra::Base)
      application.class_eval do
        @configuration = config
        def configuration
          self.class.instance_variable_get(:@configuration)
        end
        helpers Sinatra::DiversityHelper
        # Set up access logging
        configure do
          use ::Rack::CommonLogger, config.logging.access
        end
        # Set up error logging
        error 500 do |err|
          config.logging.error <<
            (Time.now.strftime('%F %T ') <<
             "#{err.class} - #{err.message}\n")
          err.backtrace.each do |step|
            config.logging.error << "\t#{step}\n"
          end
          response.headers['Content-Type'] = 'text/plain'
          halt 'Internal server error'
        end
        # If we are running a local registry, make sure we expose files from
        # the registry in a consistent way
        if config.registry.is_a?(Diversity::Registry::Local)
          get '/components/*' do
            path = File.join(config.registry.base_path, params['splat'].first)
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
          #url_info = get_url_info(config.backend, canonical_url)

          backend_url_without_scheme =
            Addressable::URI.parse(config.backend.url)
          backend_url_without_scheme.scheme = nil
          backend_url_without_scheme = backend_url_without_scheme.to_s[2..-1]

          context = {
            backend_url: backend_url_without_scheme,
            webshop_uid: url_info['webshop'],
            webshop_url: 'http://' + Addressable::URI.parse('http://' + canonical_url).host
          }

          main_component, settings =
            get_main_component_with_settings(request, {webshop: url_info['webshop']})

          # settings = Diversity::JsonSchemaCache[config.settings[:source]]

          # Render the main component
          config.engine.render(main_component, context, settings)
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
  end
end

# Helper methods used by the Diversity application
module Sinatra
  module DiversityHelper
    def call_api(meth, params, context = {}, purge_cache = false)
      # Handle caching
      cache_key = Digest::SHA2.hexdigest(
        "#{meth.inspect}#{params.inspect}#{context.inspect}"
      )
      if !purge_cache && ApiCache.cached?(cache_key)
        return ApiCache[cache_key]
      end
      payload = {
        jsonrpc: '2.0',
        method: meth,
        params: params,
        id: 1
      }
      backend_url = Addressable::URI.parse(configuration.backend.url)
      backend_context = context.merge(backend_url.query_values || {})
      backend_url.query_values = backend_context unless
        backend_context.empty?
      result = Unirest.post(backend_url.to_s, parameters: payload.to_json)
      ApiCache[cache_key] = JSON.parse(result.raw_body)['result']
      ApiCache[cache_key]
    end

    def get_canonical_url(request)
      host = request.env['HTTP_HOST']
      if configuration.environment.respond_to?(:host)
        host =
          case configuration.environment.host.type
          when 'regexp'
            host.gsub(Regexp.new(configuration.environment.host.pattern), '\1')
          when 'string'
            configuration.environment.host.name
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
        component_name = configuration.defaults.main_component.name
        component_version = configuration.defaults.main_component.version
        component_settings = configuration.defaults.settings
      end
      component =
        configuration.registry.get_component(component_name, component_version)
      fail Diversity::Exception, 'Cannot load main component ' \
           "#{component_name} (#{component_version})" unless
        component.is_a?(Diversity::Component)
      [component, Diversity::JsonObject[component_settings]]
    end

    # Class that handles caching of API calls
    class ApiCache
      # Returns an item from the cache
      #
      # @param [String] key
      # @return [Object|nil]
      def self.[](key); cache[key]; end

      # Sets an item in the cache
      #
      # @param [String] key
      # @param [String] value
      # @return [Object]
      def self.[]=(key, value); cache[key] = value; end

      # Returns whether a key exists in the cache
      #
      # @param [String] key
      # @return [true|false]
      def self.cached?(key); cache.cached?(key); end

      # Purges the cache from a single key (or all keys)
      #
      # @param [String|nil] key
      # @return [Object]
      def self.purge(key = nil)
        key.nil? ? cache.invalidate_all : cache.invalidate(key)
      end

      def self.cache; @cache ||= Cache.new; end

      private_class_method :cache
    end
  end
end
