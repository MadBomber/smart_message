require_relative "test_helper"

require 'smart_message/plugin/stdout'

class PluginTest < Minitest::Test

  def test_it_uses_plugins
    assert MyMessage.plugin.nil?
    MyMessage.config SmartMessage::StdoutPlugin
    refute MyMessage.plugin.nil?
    assert SmartMessage::StdoutPlugin == MyMessage.plugin
  end

end # class PluginTest < Minitest::Test
