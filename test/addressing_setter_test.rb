#!/usr/bin/env ruby
# test/addressing_setter_test.rb

require 'test_helper'

class AddressingSetterTest < Minitest::Test
  class TestMessage < SmartMessage::Base
    property :data
  end

  def setup
    # Reset class-level addressing before each test
    TestMessage.reset_from
    TestMessage.reset_to
    TestMessage.reset_reply_to
  end

  def test_from_setter_syntax
    # Test the new setter syntax
    TestMessage.from = 'setter-sender'
    assert_equal 'setter-sender', TestMessage.from
    
    # Test the original method syntax still works
    TestMessage.from('method-sender')
    assert_equal 'method-sender', TestMessage.from
  end

  def test_to_setter_syntax
    # Test the new setter syntax
    TestMessage.to = 'setter-receiver'
    assert_equal 'setter-receiver', TestMessage.to
    
    # Test the original method syntax still works
    TestMessage.to('method-receiver')
    assert_equal 'method-receiver', TestMessage.to
  end

  def test_reply_to_setter_syntax
    # Test the new setter syntax
    TestMessage.reply_to = 'setter-replier'
    assert_equal 'setter-replier', TestMessage.reply_to
    
    # Test the original method syntax still works
    TestMessage.reply_to('method-replier')
    assert_equal 'method-replier', TestMessage.reply_to
  end

  def test_both_syntaxes_are_equivalent
    # Set using setter syntax
    TestMessage.from = 'test-sender'
    value_from_setter = TestMessage.from
    
    # Set using method syntax
    TestMessage.from('test-sender')
    value_from_method = TestMessage.from
    
    assert_equal value_from_setter, value_from_method
  end

  def test_setter_propagates_to_instances
    TestMessage.from = 'class-sender'
    TestMessage.to = 'class-receiver'
    
    msg = TestMessage.new(data: 'test')
    
    # Instance should inherit class-level addressing
    assert_equal 'class-sender', msg.from
    assert_equal 'class-receiver', msg.to
  end
end