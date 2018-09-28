require_relative "test_helper"

require 'smart_message/plugin/stdout'

module PluginTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base

  # encapsulate the test methods
  class Test < Minitest::Test

    def test_0010_unconfigured_plugin_actions
      refute PluginTest::MyMessage.configured?

      my_message = PluginTest::MyMessage.new

      assert_raises SmartMessage::Errors::NoPluginConfigured do
        my_message.publish
      end
    end

    def test_0020_it_uses_plugins
      PluginTest::MyMessage.config SmartMessage::StdoutPlugin
      assert PluginTest::MyMessage.configured?
      assert_equal SmartMessage::StdoutPlugin, PluginTest::MyMessage.plugin
    end

  end # class PluginTest < Minitest::Test
end # module PluginTest