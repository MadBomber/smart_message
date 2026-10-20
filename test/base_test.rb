# test/base_test.rb

require_relative "test_helper"

module BaseTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    from 'test-service'
    
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base

  # Message with class description for testing
  class DescribedMessage < SmartMessage::Base
    from 'test-service'
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

    def test_to_h_has_one_symbol_key_per_property
      message = BaseTest::MyMessage.new(foo: 'one', bar: 'two')
      hash    = message.to_h

      assert_equal %i[_sm_header foo bar baz], hash.keys
      assert_equal 'one', hash[:foo]
      assert_equal 'two', hash[:bar]
      assert_nil   hash[:baz]
      assert_same  message._sm_header, hash[:_sm_header]
    end

    def test_to_hash_matches_to_h
      message = BaseTest::MyMessage.new(foo: 'one')

      assert_equal message.to_h, message.to_hash
    end

    def test_json_serializer_encodes_and_round_trips_a_message
      message = BaseTest::MyMessage.new(foo: 'one', bar: 'two', baz: 'three')
      encoded = SmartMessage::Serializer::Json.new.encode(message)

      assert_kind_of String, encoded
      decoded = JSON.parse(encoded)
      assert_equal %w[_sm_header foo bar baz], decoded.keys
      assert_equal 'three', decoded['baz']
      assert_equal 'BaseTest::MyMessage', decoded['_sm_header']['message_class']
    end

  end # class BaseTest < Minitest::Test
end # module BaseTest
