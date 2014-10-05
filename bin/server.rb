#!/usr/bin/env ruby

# Start of script
require 'optparse'
options = {}
parser = OptionParser.new do |opts|
  opts.on('-c', '--config', 'Sets the configuration file to use',
          :REQUIRED) do |config|
    options[:configuration_file] = File.expand_path(config)
  end
  opts.on('-h', '--help', 'Shows this message') {}
end

parser.parse!

unless options.key?(:configuration_file)
  puts parser.help
  exit 0
end

require_relative '../lib/diversity/server.rb'
Diversity::Server.new(options).run
