# test/header_test.rb

require_relative "test_helper"

module HeaderTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base


  class Test < Minitest::Test
    def test_header_is_useful
      m1 = BaseTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )

      refute_nil m1._sm_header

      assert_equal 'SmartMessage::Header',  m1._sm_header.class.to_s
      assert_equal 'BaseTest::MyMessage',   m1._sm_header.message_class

      m2 = BaseTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )

      refute_equal m1._sm_header.uuid, m2._sm_header.uuid

    end

  end # class Test < Minitest::Test
end # module HeaderTest
