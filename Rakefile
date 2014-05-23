desc 'Runs rubocop'
task :cop do
  sh 'rubocop --format simple' do
    # Eat rubocop errors
  end
end

desc 'Generate RDoc'
task :doc do
  sh 'rm -rf doc'
  sh 'yard'
end

desc 'Runs the test suite'
task :spec do
  sh 'rm -rf coverage'
  sh 'bacon spec/*.rb'
end

desc 'Runs the test suite'
task test: :spec
