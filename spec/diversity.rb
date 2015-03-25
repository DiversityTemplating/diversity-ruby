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

describe 'Component' do
  should 'be able to load a local component by using file path' do
    component_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components/dummy/0.0.1/diversity.json')
    )
    component = Diversity::Component.new(File.read(component_path), {base_url: '/dummy'})
    component.class.should.equal(Diversity::Component)
    component.name.should.equal('dummy')
    component.version.to_s.should.equal('0.0.1')
    component.templates.should.equal(['dummy.html'])
    component.styles.should.equal(['/dummy/css/dummy.css'])
    component.scripts.to_a.should.equal(['/dummy/js/dummy1.js', '/dummy/js/dummy2.js'])
    component.dependencies.should.equal('something-special' => '>0.0.1')
    component.pagetype.should.equal(nil)
    component.context.should.equal({})
    component.settings.class.should.equal(Diversity::JsonSchema)
    component.settings.data.should.equal({})
    component.settings.source.should.equal(nil)
    component.angular.should.equal('dummy')
    component.partials.should.equal({})
    component.themes.should.equal([])
    component.fields.should.equal({})
    component.title.should.equal(nil)
    component.thumbnail.should.equal('dummy.png')
    component.price.should.equal(nil)
    component.i18n.should.equal({})
  end

  should 'be able to load a local component by using the registry' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path)
    it '...by Rubygems version' do
      registry.available?('dummy', Gem::Version.new('0.0.1')).should.equal(true)
      comp = registry.get_component('dummy', Gem::Version.new('0.0.1'))
      comp.name.should.equal('dummy')
      comp.version.to_s.should.equal('0.0.1')
    end
    it '...by exact version string' do
      registry.available?('dummy', '0.0.1').should.equal(true)
      comp = registry.get_component('dummy', '0.0.1')
      comp.name.should.equal('dummy')
      comp.version.to_s.should.equal('0.0.1')
    end
    it '...by fuzzy version string' do
      registry.available?('dummy', '>0').should.equal(true)
      comp = registry.get_component('dummy', '>0')
      comp.name.should.equal('dummy')
      comp.version.to_s.should.equal('0.0.1')
    end
    it '...by fuzzy version string (take 2)' do
      registry.available?('dummy', '^0.0.1').should.equal(true)
      comp = registry.get_component('dummy', '^0.0.1')
      comp.name.should.equal('dummy')
      comp.version.to_s.should.equal('0.0.1')
    end
    it '...by fuzzy version string (take 3)' do
      registry.available?('something-special', '^0.5.0').should.equal(true)
      comp = registry.get_component('something-special', '^0.5.0')
      comp.name.should.equal('something-special')
      comp.version.to_s.should.equal('0.5.5')
    end

  end

  should 'be able to resolve local dependencies' do
    registry_path = File.expand_path(
      File.join(File.dirname(__FILE__), 'components')
    )
    registry = Diversity::Registry::Local.new(base_path: registry_path)
    comp = registry.get_component('weak-sauce', '0.0.4')
    comp.class.should.equal(Diversity::Component)
    comp.name.should.equal('weak-sauce')
    comp.version.to_s.should.equal('0.0.4')
    all_comps = registry.expand_component_list(comp)
    all_comps.length.should.equal(3)
    all_comps.each { |e| e.class.should.equal(Diversity::Component) }
    all_comps.first.name.should.equal('something-special')
    all_comps.first.version.to_s.should.equal('0.5.5')
    all_comps.first.settings.source.should.equal('schema.json')
    all_comps.last.name.should.equal('weak-sauce')
    all_comps.last.version.to_s.should.equal('0.0.4')
  end

  should 'fail when config file cannot be parsed as valid JSON' do
    ->() { Diversity::Component.new('yum yum', {}) }
      .should.raise(Diversity::Exception).message
      .should.match(/Failed to parse configuration/)
  end

  should 'fail when config does not validate against diversity schema' do
    ->() { Diversity::Component.new('{}', {validate_spec: true}) }
      .should.raise(Diversity::Exception).message
      .should.match(
        /The property '#\/' did not contain a required property of 'name' in schema/
      )
  end

  should 'NOT fail when config should not be validated against diversity schema' do
    # Should not raise error.
    Diversity::Component.new('{}', {validate_spec: false})
      .class.should.equal(Diversity::Component)
  end

=begin
  # This test should be reenabled when when validation is enabled again
  should 'fail when settings file cannot be parsed as valid JSON' do
    lambda do
      Diversity::Component.new(
        File.join(
          File.dirname(__FILE__), 'invalid_components', 'something-awful', '1.8.8', 'diversity.json'
        )
      )
    end
    .should.raise(Diversity::Exception).message
    .should.match(/Failed to parse settings schema/)
  end
=end

  should 'allow registry to work in different modes' do
    [:dryrun, :nowrite, :verbose].each do |mode|
      registry_path = File.expand_path(Dir.mktmpdir)
      registry = Diversity::Registry::Local.new(base_path: registry_path, mode: mode)
      registry.mode.should.equal(mode)
      FileUtils.remove_entry_secure registry_path
    end
  end

=begin
  # This test should be reenabled when the diversity-api backend is ready
  should 'be able to handle complex dependencies' do
    registry_path = File.expand_path(Dir.mktmpdir)
    begin
      registry = Diversity::Registry::Local.new(registry_path)
      registry.install_component(
        'http://diversity.io/textalk-webshop-native-components/' \
        'tws-checkout/raw/master/diversity.json'
      )
      registry.install_component(
        'http://diversity.io/textalk-webshop-native-components/' \
        'tws-bootstrap/raw/master/diversity.json'
      )
      registry.install_component(
        'http://diversity.io/textalk-webshop-native-components/' \
        'tws-api/raw/master/diversity.json'
      )
      registry.install_component(
        'http://diversity.io/textalk-webshop-native-components/' \
        'tws-schema-form/raw/master/diversity.json'
      )
      comp = registry.get_component('tws-checkout')
      comp_api = registry.get_component('tws-api')
      comp_bootstrap = registry.get_component('tws-bootstrap')
      comp_schema_form = registry.get_component('tws-schema-form')
      comp_list = registry.expand_component_list(comp)
      comp_list.length.should.equal(4)
      comp_list.all? { |c| c.is_a? Diversity::Component }.should.equal(true)
      comp_list[0].should.equal(comp_bootstrap)
      comp_list[1].should.equal(comp_api)
      comp_list[2].should.equal(comp_schema_form)
      comp_list[3].should.equal(comp)
    ensure
      FileUtils.remove_entry_secure registry_path
    end
  end
=end

end

describe 'Engine' do
  should 'render sub-components from registry when used in settings' do
    registry_path = File.expand_path(File.join(File.dirname(__FILE__), 'components_for_engine'))
    registry = Diversity::Registry::Local.new(
      base_path: registry_path,
      base_url:  'fubar:',
    )

    component = registry.get_component('toponent')

    engine = Diversity::Engine.new({registry: registry})
    #context = {'lang' => 'sv'}
    settings = {
      'sub_object' => {
        'component' => 'sub_one',
        'version'   => '1.1',
        'settings' => {
          'title' => 'FUBAR'
        }
      }
    }

    engine.render(component, {}, settings).should.equal(
      "Here is a title: ·:·FUBAR·:·\n.\n"
    )
  end
end
