# -*- coding: utf-8 -*-

require 'simplecov'
require 'simplecov-rcov'
require 'logger'
require 'coveralls'

Coveralls.wear!
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
  SimpleCov::Formatter::RcovFormatter,
  Coveralls::SimpleCov::Formatter
]
SimpleCov.command_name 'bacon'
SimpleCov.start do
  add_filter '/vendor/'
  add_filter '/spec/'
end

require 'digest/sha1'
require_relative '../lib/diversity'

describe 'Engine::Settings' do
  should 'Return a correct list of angulars' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path, base_url: 'https://dummy.domain/components')
    engine = Diversity::Engine.new(registry: registry)
    comp = registry.get_component('weak-sauce')
    engine.render(comp)
    angular = engine.send(:settings).angular
    angular.length.should.equal(1)
    angular[0].should.equal('dummy')
  end

  should 'Return a correct list of scripts' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path, base_url: 'https://dummy.domain/components')
    engine = Diversity::Engine.new(registry: registry)
    comp = registry.get_component('weak-sauce')
    engine.render(comp)
    scripts = engine.send(:settings).scripts
    scripts.length.should.equal(3)
    scripts[0].should.equal('https://dummy.domain/components/dummy/0.0.1/js/dummy1.js')
    scripts[1].should.equal('https://dummy.domain/components/dummy/0.0.1/js/dummy2.js')
    scripts[2].should.equal('https://dummy.domain/components/weak-sauce/0.0.4/weak_sauce.js')
  end

  should 'Return a correct list of unminified remote scripts' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path, base_url: 'https://dummy.domain/components')
    engine = Diversity::Engine.new(registry: registry)
    comp = registry.get_component('weak-sauce')
    engine.render(comp)
    scripts = engine.send(:settings).minified_scripts(
      base_dir: Dir.tmpdir,
      base_url: '/minified',
      filename: "7-#{Time.new(2014, 11, 11).to_i}",
      minify_remotes: false
    )
    scripts.length.should.equal(3)
    scripts[0].should.equal('https://dummy.domain/components/dummy/0.0.1/js/dummy1.js')
    scripts[1].should.equal('https://dummy.domain/components/dummy/0.0.1/js/dummy2.js')
    scripts[2].should.equal('https://dummy.domain/components/weak-sauce/0.0.4/weak_sauce.js')
    path = File.expand_path(
             File.join(Dir.tmpdir, 'scripts', "7-#{Time.new(2014, 11, 11).to_i}.min.js")
           )
    File.exist?(path).should.equal(false)
    File.unlink(path) if File.exist?(path)
  end

  should 'Return a correct list of minified local scripts' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path, base_url: registry_path)
    engine = Diversity::Engine.new(registry: registry)
    comp = registry.get_component('weak-sauce')
    engine.render(comp)
    scripts = engine.send(:settings).minified_scripts(
      base_dir: Dir.tmpdir,
      base_url: '/minified',
      filename: "7-#{Time.new(2014, 11, 11).to_i}",
      minify_remotes: false
    )
    scripts.length.should.equal(1)
    path = File.expand_path(
             File.join(Dir.tmpdir, 'scripts', "7-#{Time.new(2014, 11, 11).to_i}.min.js")
           )
    scripts[0].should.equal(path.gsub(Dir.tmpdir, '/minified'))
    File.exist?(path).should.equal(true)
    File.unlink(path) if File.exist?(path)
  end

  should 'Return a correct list of styles' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path, base_url: 'https://dummy.domain/components')
    engine = Diversity::Engine.new(registry: registry)
    comp = registry.get_component('weak-sauce')
    engine.render(comp)
    styles = engine.send(:settings).styles
    styles.length.should.equal(1)
    styles[0].should.equal('https://dummy.domain/components/dummy/0.0.1/css/dummy.css')
  end

  should 'Return a correct list of unminified remote styles' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path, base_url: 'https://dummy.domain/components')
    engine = Diversity::Engine.new(registry: registry)
    comp = registry.get_component('weak-sauce')
    engine.render(comp)
    styles = engine.send(:settings).minified_styles(
      base_dir: Dir.tmpdir,
      base_url: '/minified',
      filename: "7-#{Time.new(2014, 11, 11).to_i}",
      minify_remotes: false
    )
    styles.length.should.equal(1)
    styles[0].should.equal('https://dummy.domain/components/dummy/0.0.1/css/dummy.css')
    path = File.expand_path(
             File.join(Dir.tmpdir, 'styles', "7-#{Time.new(2014, 11, 11).to_i}.min.css")
           )
    File.exist?(path).should.equal(false)
    File.unlink(path) if File.exist?(path)
  end

  should 'Return a correct list of minified local styles' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path, base_url: registry_path)
    engine = Diversity::Engine.new(registry: registry)
    comp = registry.get_component('weak-sauce')
    engine.render(comp)
    styles = engine.send(:settings).minified_styles(
      base_dir: Dir.tmpdir,
      base_url: '/minified',
      filename: "7-#{Time.new(2014, 11, 11).to_i}",
      minify_remotes: false
    )
    styles.length.should.equal(1)
    path = File.expand_path(
             File.join(Dir.tmpdir, 'styles', "7-#{Time.new(2014, 11, 11).to_i}.min.css")
           )
    styles[0].should.equal(path.gsub(Dir.tmpdir, '/minified'))
    File.exist?(path).should.equal(true)
    File.unlink(path) if File.exist?(path)
  end
end
