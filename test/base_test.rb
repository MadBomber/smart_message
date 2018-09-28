require_relative "test_helper"

require 'smart_message/plugin/stdout'

module BaseTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base


  class Test < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil SmartMessage::VERSION
    end

    def test_it_does_something_useful
      message = BaseTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )
      assert_equal 'one',   message.foo
      assert_equal 'two',   message.bar
      assert_equal 'three', message.baz
    end

  end # class BaseTest < Minitest::Test
end # module BaseTest
