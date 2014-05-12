require 'rake'

Gem::Specification.new do |s|
  s.name                  = 'diversity'
  s.homepage              = 'https://github.com/DiversityTemplating/diversity-ruby'
  s.license               = 'MIT'
  s.authors               = ['Fredrik Liljegren', 'Lars Olsson']
  s.version               = '0.1.1'
  s.date                  = '2014-03-20'
  s.summary               = 'Diversity Templating engine.'
  s.description           = 'Diversity Templating engine.'
  s.files                 = FileList['lib/**/*.rb', '[A-Z]*', 'spec/**/*.rb'].to_a
  s.platform              = Gem::Platform::RUBY
  s.require_path          = 'lib'
  s.required_ruby_version = '>= 1.9.0'

  s.add_dependency('json-rpc-client')
  s.add_dependency('json-schema', '=2.2.1')

  s.add_development_dependency('bacon')
  s.add_development_dependency('rake')
  s.add_development_dependency('coveralls')
  s.add_development_dependency('simplecov')
  s.add_development_dependency('simplecov-rcov')
end
