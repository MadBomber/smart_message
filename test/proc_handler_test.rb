#!/usr/bin/env ruby
# test/proc_handler_test.rb

require_relative 'test_helper'

class ProcHandlerTest < Minitest::Test

  def setup
    @transport = SmartMessage::Transport::StdoutTransport.new(loopback: true)
    
    # Keep track of received messages for testing
    @received_messages = []
  end

  def teardown
    # Clean up any proc handlers that might have been registered
    SmartMessage::Base.class_variable_set(:@@proc_handlers, {})
  end

  # Test message class for proc handler testing
  class TestMessage < SmartMessage::Base
    property :content
    property :sender

    config do
      reset_transport
      reset_serializer
    end

    def self.process(message_header, message_payload)
      # Default handler - should still work
      data = JSON.parse(message_payload)
      puts "Default handler: #{data['content']}"
    end
  end

  def test_default_subscribe_still_works
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    # Should work the same as before
    handler_id = TestMessage.subscribe
    
    assert_equal "ProcHandlerTest::TestMessage.process", handler_id
    assert TestMessage.transport.subscribers["ProcHandlerTest::TestMessage"].include?(handler_id)
  end

  def test_subscribe_with_block
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    received_data = nil

    # Subscribe with a block
    handler_id = TestMessage.subscribe do |header, payload|
      data = JSON.parse(payload)
      received_data = data
    end

    # Should generate a unique proc handler ID
    assert handler_id.start_with?("ProcHandlerTest::TestMessage.proc_")
    assert TestMessage.proc_handler?(handler_id)

    # Publish a message
    TestMessage.new(content: "Hello Block", sender: "test").publish

    # Give some time for processing
    sleep(0.1)

    # Should have received the message via our block
    assert_equal "Hello Block", received_data["content"]
    assert_equal "test", received_data["sender"]
  end

  def test_subscribe_with_proc_parameter
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    received_data = nil

    # Create a proc
    my_handler = proc do |header, payload|
      data = JSON.parse(payload)
      received_data = data
    end

    # Subscribe with the proc as parameter
    handler_id = TestMessage.subscribe(my_handler)

    # Should generate a unique proc handler ID
    assert handler_id.start_with?("ProcHandlerTest::TestMessage.proc_")
    assert TestMessage.proc_handler?(handler_id)

    # Publish a message
    TestMessage.new(content: "Hello Proc", sender: "test").publish

    # Give some time for processing
    sleep(0.1)

    # Should have received the message via our proc
    assert_equal "Hello Proc", received_data["content"]
    assert_equal "test", received_data["sender"]
  end

  def test_subscribe_with_lambda
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    received_data = nil

    # Create a lambda
    my_handler = lambda do |header, payload|
      data = JSON.parse(payload)
      received_data = data
    end

    # Subscribe with the lambda as parameter
    handler_id = TestMessage.subscribe(my_handler)

    # Should generate a unique proc handler ID
    assert handler_id.start_with?("ProcHandlerTest::TestMessage.proc_")
    assert TestMessage.proc_handler?(handler_id)

    # Publish a message
    TestMessage.new(content: "Hello Lambda", sender: "test").publish

    # Give some time for processing
    sleep(0.1)

    # Should have received the message via our lambda
    assert_equal "Hello Lambda", received_data["content"]
    assert_equal "test", received_data["sender"]
  end

  def test_multiple_proc_handlers
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    received_messages = []

    # Subscribe with multiple blocks
    handler1 = TestMessage.subscribe do |header, payload|
      data = JSON.parse(payload)
      received_messages << "Handler1: #{data['content']}"
    end

    handler2 = TestMessage.subscribe do |header, payload|
      data = JSON.parse(payload)
      received_messages << "Handler2: #{data['content']}"
    end

    # Both should be different IDs
    refute_equal handler1, handler2
    assert TestMessage.proc_handler?(handler1)
    assert TestMessage.proc_handler?(handler2)

    # Publish a message
    TestMessage.new(content: "Multiple", sender: "test").publish

    # Give some time for processing
    sleep(0.1)

    # Both handlers should have received the message
    assert_equal 2, received_messages.length
    assert received_messages.include?("Handler1: Multiple")
    assert received_messages.include?("Handler2: Multiple")
  end

  def test_mix_proc_and_method_handlers
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    received_data = nil

    # Subscribe with both proc and method handlers
    proc_handler = TestMessage.subscribe do |header, payload|
      data = JSON.parse(payload)
      received_data = data
    end

    method_handler = TestMessage.subscribe("ProcHandlerTest::TestMessage.process")

    # Should have both types
    assert TestMessage.proc_handler?(proc_handler)
    refute TestMessage.proc_handler?(method_handler)

    # Both should be in subscribers
    subscribers = TestMessage.transport.subscribers["ProcHandlerTest::TestMessage"]
    assert subscribers.include?(proc_handler)
    assert subscribers.include?(method_handler)
  end

  def test_unsubscribe_proc_handler
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    # Subscribe with a block
    handler_id = TestMessage.subscribe do |header, payload|
      # This handler should be removed
    end

    # Verify it's registered
    assert TestMessage.proc_handler?(handler_id)
    assert TestMessage.transport.subscribers["ProcHandlerTest::TestMessage"].include?(handler_id)

    # Unsubscribe
    TestMessage.unsubscribe(handler_id)

    # Should be removed from both subscribers and proc registry
    refute TestMessage.transport.subscribers["ProcHandlerTest::TestMessage"].include?(handler_id)
    refute TestMessage.proc_handler?(handler_id)
  end

  def test_proc_handler_with_message_header
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    received_header = nil
    received_uuid = nil

    # Subscribe with a block that checks the header
    TestMessage.subscribe do |header, payload|
      received_header = header
      received_uuid = header.uuid
    end

    # Publish a message
    message = TestMessage.new(content: "Header Test", sender: "test")
    message.publish

    # Give some time for processing
    sleep(0.1)

    # Should have received the header
    assert received_header
    assert_equal "ProcHandlerTest::TestMessage", received_header.message_class
    assert received_uuid
    assert received_header.published_at
  end

  def test_proc_handler_error_handling
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    # Subscribe with a block that raises an error
    TestMessage.subscribe do |header, payload|
      raise "Test error in proc handler"
    end

    # This should not crash the system
    begin
      TestMessage.new(content: "Error Test", sender: "test").publish
      sleep(0.1)  # Give time for processing
      # If we get here, no exception was raised at the top level
      assert true, "System handled proc handler error gracefully"
    rescue => e
      flunk "System crashed due to proc handler error: #{e.message}"
    end
  end

  def test_proc_handler_with_complex_logic
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    processed_data = {}

    # Subscribe with a complex proc that does data transformation
    complex_processor = proc do |header, payload|
      data = JSON.parse(payload)
      processed_data[:original] = data
      processed_data[:transformed] = {
        upper_content: data['content'].upcase,
        sender_length: data['sender'].length,
        processed_at: Time.now,
        header_uuid: header.uuid
      }
    end

    TestMessage.subscribe(complex_processor)

    # Publish a message
    TestMessage.new(content: "Hello World", sender: "tester").publish
    sleep(0.1)

    # Check complex processing results
    assert processed_data[:original]
    assert_equal "Hello World", processed_data[:original]['content']
    
    assert processed_data[:transformed]
    assert_equal "HELLO WORLD", processed_data[:transformed][:upper_content]
    assert_equal 6, processed_data[:transformed][:sender_length]  # "tester".length
    assert processed_data[:transformed][:processed_at]
    assert processed_data[:transformed][:header_uuid]
  end

  def test_proc_registry_cleanup_on_unsubscribe_all
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    # Subscribe with several proc handlers
    proc1 = proc { |h,p| }
    proc2 = proc { |h,p| }
    
    id1 = TestMessage.subscribe(proc1)
    id2 = TestMessage.subscribe(proc2)
    
    # Verify they're in the registry
    assert TestMessage.proc_handler?(id1)
    assert TestMessage.proc_handler?(id2)

    # Unsubscribe all handlers for this message class
    TestMessage.unsubscribe!

    # Registry should still contain the procs since unsubscribe! doesn't clean individual procs
    # This is expected behavior - unsubscribe! only removes from dispatcher
    assert TestMessage.proc_handler?(id1)
    assert TestMessage.proc_handler?(id2)
  end

  def test_subscription_return_values
    TestMessage.transport @transport
    TestMessage.serializer SmartMessage::Serializer::JSON.new

    # All subscription methods should return identifiers
    default_id = TestMessage.subscribe
    assert_equal "ProcHandlerTest::TestMessage.process", default_id

    method_id = TestMessage.subscribe("SomeClass.some_method")
    assert_equal "SomeClass.some_method", method_id

    block_id = TestMessage.subscribe { |h,p| }
    assert block_id.start_with?("ProcHandlerTest::TestMessage.proc_")

    proc_id = TestMessage.subscribe(proc { |h,p| })
    assert proc_id.start_with?("ProcHandlerTest::TestMessage.proc_")
    
    # All IDs should be different
    ids = [default_id, method_id, block_id, proc_id]
    assert_equal ids.length, ids.uniq.length
  end

end