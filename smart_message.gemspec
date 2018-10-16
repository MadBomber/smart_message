# smart_message.gemspec

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'smart_message/version'

Gem::Specification.new do |spec|
  spec.name          = 'smart_message'
  spec.version       = SmartMessage::VERSION
  spec.authors       = ['Dewayne VanHoozer']
  spec.email         = ['dvanhoozer@gmail.com']

  spec.homepage      = "https://github.com/MadBomber/smart_message"
  spec.summary       = %q{An abstraction to protect message content from the backend delivery broker.}
  spec.description   = <<~DESCRIPTION
    Much like ActiveRecord abstracts the model as an ORM from the
    backend data-store, SmartMessage abstracts the message from
    its backend broker processes.
  DESCRIPTION

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path(__dir__, __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'hashie',         '~> 3.6'
  spec.add_dependency 'activesupport'
  spec.add_dependency 'concurrent-ruby',    '~> 1.0'
  spec.add_dependency 'concurrent-ruby-ext','~> 1.0'

  spec.add_development_dependency 'bundler',  '~> 1.16'
  spec.add_development_dependency 'rake',     '~> 12.3'
  spec.add_development_dependency 'minitest', '~> 5.11'
  spec.add_development_dependency 'shoulda',  '~> 3.6'
  spec.add_development_dependency 'minitest-power_assert',  '~> 0.3'

  spec.add_development_dependency 'awesome_print'
  spec.add_development_dependency 'debug_me'

end
