# test/base_test.rb

require_relative "test_helper"

module BaseTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base

  # Message with class description for testing
  class DescribedMessage < SmartMessage::Base
    description "Test message with class-level description"
    property :data
  end


  class Test < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil SmartMessage::VERSION
    end

    def test_it_does_something_useful
      m1 = BaseTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )
      assert_equal 'one',   m1.foo
      assert_equal 'two',   m1.bar
      assert_equal 'three', m1.baz

      refute_nil m1._sm_header

      assert_equal 'SmartMessage::Header',  m1._sm_header.class.to_s
      assert_equal 'BaseTest::MyMessage',   m1._sm_header.message_class

      m2 = BaseTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )

      refute_equal m1._sm_header.uuid, m2._sm_header.uuid

    end

    def test_class_level_description
      # Test that a message with description returns it
      assert_equal "Test message with class-level description", BaseTest::DescribedMessage.description
      
      # Test that a message without description returns default
      assert_equal "BaseTest::MyMessage is a SmartMessage", BaseTest::MyMessage.description
      
      # Test that we can set a description on a class that doesn't have one
      BaseTest::MyMessage.description "Added description for MyMessage"
      assert_equal "Added description for MyMessage", BaseTest::MyMessage.description
      
      # Reset it back to nil for other tests
      BaseTest::MyMessage.instance_variable_set(:@description, nil)
      assert_equal "BaseTest::MyMessage is a SmartMessage", BaseTest::MyMessage.description
    end

  end # class BaseTest < Minitest::Test
end # module BaseTest
