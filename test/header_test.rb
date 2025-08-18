# test/header_test.rb

require_relative "test_helper"

module HeaderTest
  # A simple example message model
  class MyMessage < SmartMessage::Base
    from 'header-test-service'
    
    property :foo
    property :bar
    property :baz
  end # class MyMessage < SmartMessage::Base


  class Test < Minitest::Test
    def test_header_is_useful
      m1 = HeaderTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )

      refute_nil m1._sm_header

      assert_equal 'SmartMessage::Header',  m1._sm_header.class.to_s
      assert_equal 'HeaderTest::MyMessage',   m1._sm_header.message_class

      m2 = HeaderTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )

      refute_equal m1._sm_header.uuid, m2._sm_header.uuid
    end

    def test_header_contains_addressing_fields
      message = HeaderTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )
      
      header = message._sm_header
      
      # Test that addressing fields exist
      assert_respond_to header, :from
      assert_respond_to header, :to
      assert_respond_to header, :reply_to
      
      # Test values from class configuration
      assert_equal 'header-test-service', header.from
      assert_nil header.to
      assert_nil header.reply_to
    end

    def test_header_addressing_field_types
      message = HeaderTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )
      
      header = message._sm_header
      
      # Verify field types
      assert_instance_of String, header.from
      assert header.to.nil? || header.to.is_a?(String)
      assert header.reply_to.nil? || header.reply_to.is_a?(String)
    end

    def test_header_addressing_validation
      message = HeaderTest::MyMessage.new(
        foo: 'one', bar: 'two', baz: 'three'
      )
      
      header = message._sm_header
      
      # Header should validate successfully with required 'from' field
      assert header.valid?
      assert_empty header.validation_errors
      
      # Validate! should not raise
      begin
        header.validate!
        assert true, "header.validate! should not raise"
      rescue => e
        flunk "header.validate! raised #{e.class}: #{e.message}"
      end
    end

  end # class Test < Minitest::Test
end # module HeaderTest
