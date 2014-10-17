require 'ostruct'
require_relative '../exception.rb'

module Diversity
  class Server
    class Configuration

      attr_reader :backend,
                  :configuration,
                  :defaults,
                  :engine,
                  :environment,
                  :logging,
                  :registry,
                  :server

      # Initializes a new Diversity::Server::Configuration instance
      #
      # @param [String] source
      # @return [Diversity::Server::Configuration
      def initialize(source)
        @configuration_source = source
        @backend = @configuration = @defaults = @engine = @environment =
          @logging = @registry = @server = nil
        load_from_file(File.expand_path(@configuration_source))
      end

      private

      # Converts a Hash into an OpenStruct recursively
      #
      # @param [Hash] hsh
      # @return [OpenStruct]
      def hash2struct(hsh)
        return hsh unless hsh.is_a?(Hash)
        os = OpenStruct.new
        hsh.each_pair do |k, v|
          if v.is_a?(Hash)
            os[k] = hash2struct(v)
          else
            os[k] = v
          end
        end
        os
      end

      def init_backend
        @backend = @configuration.key?(:backend) &&
                   @configuration[:backend].is_a?(Hash) ?
                   hash2struct(@configuration[:backend]) : nil
      end

      def init_defaults
        @defaults = OpenStruct.new
        @defaults.main_component = OpenStruct.new
        if @configuration.key?(:defaults) &&
           @configuration[:defaults].key?(:main_component) &&
           @configuration[:defaults][:main_component].is_a?(Hash)
          @defaults.main_component.name =
            @configuration[:defaults][:main_component].fetch(:name, 'tws-theme')
          @defaults.main_component.version =
            @configuration[:defaults][:main_component].fetch(:version, '*')
        else
          @defaults.main_component.name = 'tws-theme'
          @defaults.main_component.version = '*'
        end
        
        if @configuration.key?(:defaults) &&
           @configuration[:defaults].key?(:settings) &&
           @configuration[:defaults][:settings].is_a?(Hash) &&
           @configuration[:defaults][:settings].key?(:source)
          @defaults.settings =
            JSON.parse(
              File.read(@configuration[:defaults][:settings][:source])
            )
        else
          @defaults.settings = {}
        end
        
      end

      def init_engine
        engine_options = { registry: @registry }
        # If we are using a local repository, expose component files
        if @registry.is_a?(Diversity::Registry::Local)
          engine_options[:public_path] = '/components'
        end
        if @logging.debug
          engine_options[:debug_logger] = @logging.debug
        end
        @engine = Diversity::Engine.new(engine_options)
      end

      def init_environment
        @environment = @configuration.key?(:environment) &&
                       @configuration[:environment].is_a?(Hash) ?
                       hash2struct(@configuration[:environment]) : nil
      end

      def init_loggers
        require 'logger'
        @logging = OpenStruct.new
        ::Logger.class_eval { alias :write :'<<' }
        if @configuration.key?(:logging)
          access_log = @configuration[:logging].fetch(:access, $stdout)
          access_log = File.expand_path(access_log) unless
            access_log == $stdout
          debug_log = @configuration[:logging].fetch(:debug, nil)
          debug_log = File.expand_path(debug_log) unless debug_log.nil?
          error_log = @configuration[:logging].fetch(:error, $stderr)
          error_log = File.expand_path(error_log) unless
            error_log == $stdout
        else
          access_log = $stdout
          debug_log = nil
          error_log = $stderr
        end
        @logging.access = Logger.new(access_log)
        @logging.debug = Logger.new(debug_log) unless debug_log.nil?
        @logging.error = Logger.new(error_log)
      end

      def init_registry
        config = @configuration[:registry]
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
        @registry = registry_class.new(config[:options] || {})
      end

      def init_server_settings
        hsh = @configuration.key?(:server) &&
              @configuration[:server].is_a?(Hash) ?
              @configuration[:server] : {}
        @server = OpenStruct.new(hsh)
      end

      # Loads the server configuration from a file
      #
      # @param [String] path
      # @return nil
      def load_from_file(path)
        fail Diversity::Exception,
            "Configuration file #{path} is not readable.", caller unless
          File.exist?(path) && File.readable?(path)
        require 'json'
        begin
          @configuration =
            JSON.parse(File.read(path), symbolize_names: true)
          parse
          nil
        rescue Exception
          fail Diversity::Exception,
               "Failed to parse configuration file #{path}. " \
               'It does not contain valid JSON.', caller
        end
      end

      # Parses configuration data and initializes relevant objects
      #
      # @param [config] Hash
      # @return nil
      def parse
        init_loggers
        init_backend
        init_environment
        init_server_settings
        require_relative '../../diversity.rb'
        init_registry
        init_engine
        init_defaults
        nil
      end
    end
  end
end
