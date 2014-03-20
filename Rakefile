desc 'Runs the test suite'
task :test do
  sh 'rm -rf coverage'
  sh "bacon spec/component.rb"
end

desc "Run tests"
task :default => :test
