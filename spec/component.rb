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
require_relative '../lib/diversity/component.rb'
require_relative '../lib/diversity/registry.rb'

class ComponentHelper

end

describe 'Component' do
  should 'be able to load a local component by using file path' do
    component_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components/dummy/0.0.1/diversity.json')
    )
    component = Diversity::Component.new(component_path)
    component.class.should.equal(Diversity::Component)
    component.name.should.equal('dummy')
    component.version.to_s.should.equal('0.0.1')
    component.templates.should.equal(['dummy.html'])
    component.styles.should.equal(['css/dummy.css'])
    component.scripts.to_a.should.equal(['js/dummy1.js', 'js/dummy2.js'])
    component.dependencies.should.equal({})
    component.type.should.equal('object')
    component.pagetype.should.equal(nil)
    component.context.should.equal({})
    component.options.should.equal({})
    component.angular.should.equal('dummy')
    component.partials.should.equal({})
    component.themes.should.equal([])
    component.fields.should.equal({})
    component.title.should.equal(nil)
    component.thumbnail.should.equal('dummy.png')
    component.price.should.equal(nil)
    component.assets.should.equal([])
    component.src.should.equal component_path
    component.i18n.should.equal({})
    component.base_path.should.equal(File.dirname(component_path))
    component.checksum.should.equal(Digest::SHA1.hexdigest(component.dump))
  end

  should 'be able to load a local component by using the registry' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry.new(registry_path)
    it '...by Rubygems version' do
      registry.has_component?('dummy', Gem::Version.new('0.0.1')).should.equal(true)
      comp = registry.get_component('dummy', Gem::Version.new('0.0.1'))
      comp.name.should.equal('dummy')
      comp.version.to_s.should.equal('0.0.1')
    end
    it '...by exact version string' do
      registry.has_component?('dummy', '0.0.1').should.equal(true)
      comp = registry.get_component('dummy', '0.0.1')
      comp.name.should.equal('dummy')
      comp.version.to_s.should.equal('0.0.1')
    end
    it '...by fuzzy version string' do
      registry.has_component?('dummy', '>0').should.equal(true)
      comp = registry.get_component('dummy', '>0')
      comp.name.should.equal('dummy')
      comp.version.to_s.should.equal('0.0.1')
    end
  end

  should 'be able to resolve local dependencies' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry.new(registry_path)
    comp = registry.get_component('weak-sauce', '0.0.4')
    comp.class.should.equal(Diversity::Component)
    comp.name.should.equal('weak-sauce')
    comp.version.to_s.should.equal('0.0.4')
    all_comps = registry.expand_component_list(comp)
    all_comps.length.should.equal(2)
    all_comps.each { |e| e.class.should.equal(Diversity::Component) }
    all_comps.first.name.should.equal('dummy')
    all_comps.first.version.to_s.should.equal('0.0.1')
    all_comps.last.name.should.equal('weak-sauce')
    all_comps.last.version.to_s.should.equal('0.0.4')
  end

end
