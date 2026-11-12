# test/packaging_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require 'rubygems/package'

# What ships in the gem and how it loads (review findings P1 to P6).
class PackagingTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def spec
    @spec ||= Dir.chdir(ROOT) { Gem::Specification.load('smart_message.gemspec') }
  end

  def test_every_file_loads_under_zeitwerk
    Zeitwerk::Loader.eager_load_all # raises Zeitwerk::NameError on a file/constant mismatch

    %w[Base Header Dispatcher Envelope PublishResult Stats DeadLetterQueue Configuration
       DDQ::Memory DDQ::Redis Logger::Null Logger::Default Logger::Lumberjack
       Serializer::Json Transport::MemoryTransport Transport::StdoutTransport
       Transport::FileTransport Transport::RedisTransport].each do |name|
      assert SmartMessage.const_get(name), "SmartMessage::#{name} should be defined"
    end
  end

  def test_no_lib_file_bypasses_the_autoloader
    offenders = Dir[File.join(ROOT, 'lib', '**', '*.rb')].select do |file|
      File.read(file).match?(/^\s*require_relative\b/)
    end

    assert_equal ['lib/smart_message.rb'], offenders.map { |file| file.delete_prefix("#{ROOT}/") },
                 'only the entry point may use require_relative (for version.rb)'
  end

  def test_the_gem_ships_only_what_it_needs
    files = spec.files

    refute_empty files
    files.each { |file| assert File.file?(File.join(ROOT, file)), "#{file} is listed but missing" }

    unexpected = files.reject { |file| file.start_with?('lib/') || file.match?(/\A(README\.md|CHANGELOG\.md|LICENSE(\.\w+)?)\z/) }
    assert_empty unexpected, 'only lib/, the README, the changelog and the license belong in the gem'

    assert_empty files.grep(/\.(log|jsonl|backup|iml|xml)\z/)
    assert_empty files.grep(%r{(\A|/)\.}), 'no dot files or editor directories'
    assert_equal Dir.chdir(ROOT) { Dir['lib/**/*.rb'].sort }, files.grep(%r{\Alib/}).sort
  end

  def test_the_built_gem_contains_exactly_the_listed_files
    gem_file = temp_path('smart_message.gem')

    Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
      Dir.chdir(ROOT) { Gem::Package.build(spec.dup, false, false, gem_file) }
    end
    contents = Gem::Package.new(gem_file).contents

    assert_equal spec.files.sort, contents.sort
    assert_includes contents, 'lib/smart_message.rb'
    assert_empty contents.grep(%r{\A(test|examples|docs|log|site)/})
  end

  def test_no_debris_in_lib
    stray = Dir.glob(File.join(ROOT, 'lib', '**', '*'), File::FNM_DOTMATCH).reject do |entry|
      File.directory?(entry) || entry.end_with?('.rb')
    end

    assert_empty stray.map { |entry| entry.delete_prefix("#{ROOT}/") }
  end

  def test_version_and_ruby_requirement
    assert_equal SmartMessage::VERSION, spec.version.to_s
    assert_match(/\A\d+\.\d+\.\d+\z/, SmartMessage::VERSION)
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new(RUBY_VERSION.split('-').first))
    refute spec.required_ruby_version.satisfied_by?(Gem::Version.new('3.3.0'))
  end

  def test_runtime_dependencies_are_the_ones_the_code_requires
    assert_equal %w[breaker_machines concurrent-ruby hashie lumberjack redis zeitwerk],
                 spec.runtime_dependencies.map(&:name).sort
  end

  def test_removed_features_are_gone
    %w[SimpleStats MilClass].each { |name| refute Object.const_defined?(name), "#{name} should not be defined" }

    %w[AsyncPublishQueue FifoOperations FileOperations FileWatching PartitionedFiles].each do |name|
      refute SmartMessage::Transport.const_defined?(name, false), "Transport::#{name} was removed"
    end
  end
end
