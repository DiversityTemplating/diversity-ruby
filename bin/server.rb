#!/usr/bin/env ruby

require 'unirest'

def check_ruby_version
  if RUBY_VERSION.split('.').first.to_i != 2
    exit_with_error 'Server will only ruby on ruby version 2. ' \
                    "You are running version #{RUBY_VERSION}." unless
      RUBY_VERSION.split('.').first.to_i == 2
  end
end

def exit_with_error(message)
  puts message
  exit 1
end

def load_sinatra_or_die
  begin
    gem 'sinatra'
  rescue LoadError
    exit_with_error 'Failed to load sinatra. ' \
         'Please install sinatra before continuing.'
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
  exit_with_error 'Configuration does not specify a registry type.' unless
    config.key?(:type)
  begin
    registry_class =
      Diversity::Registry.const_get(config[:type])
  rescue NameError
    exit_with_error 'Configuration specifies invalid registry type ' \
                    "#{config[:type]}."
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

def parse_configuration(config)
  backend = config[:backend] || nil
  require_relative '../lib/diversity.rb'
  registry = get_registry(config[:registry] || {})
  engine_options = {registry: registry}
  # If we are using a local repository, expose component files
  if registry.is_a?(Diversity::Registry::Local)
    engine_options[:public_path] = '/components'
  end
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
  main_component = registry.get_component(mc_name, mc_version)
  fail "Cannot load main component #{mc_name} (#{mc_version})" unless
    main_component.is_a?(Diversity::Component)
  {
    backend:        backend,
    environment:    config[:environment] || {},
    engine:         Diversity::Engine.new(engine_options),
    main_component: main_component,
    registry:       registry
  }
end

def parse_config_file(file)
  exit_with_error "Configuration file #{file} is not readable." unless
    File.exist?(file) && File.readable?(file)
  require 'json'
  begin
    JSON.parse(File.read(file), symbolize_names: true)
  rescue
    exit_with_error "Failed to parse configuration file #{file}. " \
                    'It does not contain valid JSON.'
  end
end

# Start of script
check_ruby_version
load_sinatra_or_die

require 'optparse'
options = {}
OptionParser.new do |opts|
  opts.on('-c', '--config', 'Sets the configuration file to use',
          :REQUIRED) do |config|
    options[:configuration_file] = File.expand_path(config)
  end
  opts.on('-h', '--help', 'Shows this message') do
    puts opts
  end
end.parse(ARGV)

options[:configuration] =
  parse_config_file(options[:configuration_file])

options = options.merge(parse_configuration(options[:configuration]))

# Configuration seems ok, time to start sinatra
# ...but clear ARGV first, otherwise sinatra will try to parse it
ARGV.clear
require 'sinatra'

# Look for sinatra settings
# Available settings can be found at
# http://rubydoc.info/gems/sinatra#Available_Settings
if options[:configuration].key?(:server)
  configure do
    options[:configuration][:server].each_pair do |key, value|
      set key, value
    end
  end
end

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
