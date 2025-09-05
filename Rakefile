require "bundler/gem_tasks"
require "rake/testtask"

# Main test task - runs all tests with proper environment setup
task :test do
  ENV['SM_LOGGER_TEST'] = 'true'
  
  puts "Running SmartMessage test suite..."
  puts "=" * 40
  
  # Check for Redis availability for informational purposes
  begin
    require 'redis'
    redis = Redis.new(url: 'redis://localhost:6379')
    redis.ping
    puts "✅ Redis available - all tests including Redis Queue Transport will run"
    redis.quit
  rescue => e
    puts "⚠️  Redis not available: #{e.message}"
    puts "   Redis Queue Transport tests will be skipped automatically"
  end
  
  puts ""
  
  # Run the actual tests
  Rake::TestTask.new(:run_tests) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/**/*_test.rb"]
  end
  
  Rake::Task[:run_tests].invoke
end

task :default => :test
