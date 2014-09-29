#!/usr/bin/env ruby

require 'pp'

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

def parse_configuration(config)
  exit_with_error 'Configuration does not specify a registry.' unless
    config.key?(:registry)
  exit_with_error 'Configuration does not specify a registry type.' unless
    config[:registry].key?(:type)
  require_relative '../lib/diversity.rb'
  begin
    registry_class =
      Diversity::Registry.const_get(config[:registry][:type])
  rescue NameError
    exit_with_error 'Configuration specifies invalid registry type ' \
                    "#{config[:registry][:type]}."
  end
  registry = registry_class.new(config[:registry][:options])
  engine_options = {registry: registry}
  # If we are using a local repository, expose component files
  if registry.is_a?(Diversity::Registry::Local)
    engine_options[:public_path] = '/components'
  end
  { engine: Diversity::Engine.new(engine_options), registry: registry }
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
  options[:configuration][:server]
  configure do
    options[:configuration][:server].each_pair do |key, value|
      set key, value
    end
  end
end

get '/' do
  # For now, we use the same context for all requests
  context = options[:configuration][:context]

  # For now, we use the same settings for all requests
  settings =
    Diversity::JsonSchemaCache[options[:configuration][:settings][:source]]

  # Load theme component
  theme_component = options[:registry].get_component('tws-theme')
  options[:engine].render(theme_component, context, settings)
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
