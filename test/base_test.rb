require_relative "test_helper"

require 'smart_message/plugin/stdout'


class BaseTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil SmartMessage::VERSION
  end

  def test_it_does_something_useful
    message = MyMessage.new(foo: 'one', bar: 'two', baz: 'three')
    assert 'one'    == message.foo
    assert 'two'    == message.bar
    assert 'three'  == message.baz
  end

end # class BaseTest < Minitest::Test
