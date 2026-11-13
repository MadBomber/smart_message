# smart_message.gemspec

require_relative 'lib/smart_message/version'

Gem::Specification.new do |spec|
  spec.name          = 'smart_message'
  spec.version       = SmartMessage::VERSION
  spec.authors       = ['Dewayne VanHoozer']
  spec.email         = ['dvanhoozer@gmail.com']

  spec.homepage      = "https://madbomber.github.io/smart_message/"
  spec.summary       = %q{An abstraction to protect message content from the backend delivery transport.}
  spec.description   = <<~DESCRIPTION
    Much like ActiveRecord abstracts the model as an ORM from the
    backend data-store, SmartMessage abstracts the message from
    its backend transport processes.
  DESCRIPTION

  spec.metadata = {
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => "https://github.com/MadBomber/smart_message",
    "changelog_uri"     => "https://github.com/MadBomber/smart_message/blob/main/CHANGELOG.md",
    "bug_tracker_uri"   => "https://github.com/MadBomber/smart_message/issues",
    "documentation_uri" => "https://madbomber.github.io/smart_message/getting-started/quick-start/"
  }

  # Only the library and its top-level documents are packaged.  The paths
  # are resolved from this file's directory, so the gem builds the same way
  # from any working directory.
  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*.rb', 'README.md', 'CHANGELOG.md', 'LICENSE*']
  end
  spec.require_paths = ['lib']

  # breaker_machines 0.21 requires Ruby 4.0
  spec.required_ruby_version = '>= 4.0'

  spec.add_dependency 'breaker_machines', '~> 0.21'
  spec.add_dependency 'concurrent-ruby',  '~> 1.3'
  spec.add_dependency 'hashie',           '~> 5.0'
  spec.add_dependency 'lumberjack',       '~> 2.0'
  spec.add_dependency 'redis',            '>= 5.0', '< 7'
  spec.add_dependency 'zeitwerk',         '~> 2.6'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'mutex_m'
  spec.add_development_dependency 'shoulda'
  spec.add_development_dependency 'minitest-power_assert'
  spec.add_development_dependency 'minitest-mock'  # Minitest::Mock moved out of minitest 6

  spec.add_development_dependency 'amazing_print'
  spec.add_development_dependency 'benchmark'      # a bundled gem since Ruby 3.5; used by the examples
  spec.add_development_dependency 'debug_me'
end
