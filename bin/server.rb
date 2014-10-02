#!/usr/bin/env ruby

# Start of script
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

exit 0 unless options.key?(:configuration_file)

require_relative '../lib/diversity/server.rb'
server = Diversity::Server.new(options)
server.run

exit 0

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
