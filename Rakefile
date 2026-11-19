require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

desc "Run every example script and fail if one of them fails"
task :examples do
  ruby "examples/run_all.rb"
end

task :default => :test
