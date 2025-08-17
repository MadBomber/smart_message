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
  spec.summary       = %q{An abstraction to protect message content from the backend delivery transport.}
  spec.description   = <<~DESCRIPTION
    Much like ActiveRecord abstracts the model as an ORM from the
    backend data-store, SmartMessage abstracts the message from
    its backend transport processes.
  DESCRIPTION

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path(__dir__, __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.0.0'

  spec.add_dependency 'hashie'
  spec.add_dependency 'activesupport'
  spec.add_dependency 'concurrent-ruby'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'mutex_m'
  spec.add_development_dependency 'shoulda'
  spec.add_development_dependency 'minitest-power_assert'

  spec.add_development_dependency 'amazing_print'
  spec.add_development_dependency 'debug_me'

end
