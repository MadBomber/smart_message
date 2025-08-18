#!/usr/bin/env ruby
# test/proc_handler_integration_test.rb

require_relative 'test_helper'

class ProcHandlerIntegrationTest < Minitest::Test

  def setup
    # Clean up any leftover proc handlers
    SmartMessage::Base.class_variable_set(:@@proc_handlers, {})
  end

  def teardown
    # Clean up proc handlers after each test
    SmartMessage::Base.class_variable_set(:@@proc_handlers, {})
  end

  # Test service class for method handler testing
  class TestService
    @@method_calls = []

    def self.handle_message(header, payload)
      data = JSON.parse(payload)
      @@method_calls << "METHOD:#{data['message_id']}"
    end

    def self.method_calls
      @@method_calls
    end

    def self.clear_method_calls
      @@method_calls = []
    end
  end

  # Integration test message
  class IntegrationTestMessage < SmartMessage::Base
    from 'test-service'
    
    property :message_id
    property :content
    property :timestamp

    config do
      reset_transport
      reset_serializer
    end

    def self.process(message_header, message_payload)
      data = JSON.parse(message_payload)
      @default_processed ||= []
      @default_processed << data['message_id']
    end

    def self.default_processed
      @default_processed ||= []
    end

    def self.clear_default_processed
      @default_processed = []
    end
  end

  def test_proc_handlers_with_memory_transport
    IntegrationTestMessage.transport SmartMessage::Transport::MemoryTransport.new(auto_process: true)
    IntegrationTestMessage.serializer SmartMessage::Serializer::JSON.new

    received_messages = []

    # Subscribe with a proc
    message_processor = proc do |header, payload|
      data = JSON.parse(payload)
      received_messages << {
        id: data['message_id'],
        content: data['content'],
        header_class: header.message_class
      }
    end

    handler_id = IntegrationTestMessage.subscribe(message_processor)

    # Also test default handler
    IntegrationTestMessage.subscribe

    # Clear any previous state
    IntegrationTestMessage.clear_default_processed

    # Publish a message
    message = IntegrationTestMessage.new(
      message_id: "PROC-001",
      content: "Test proc integration",
      timestamp: Time.now.iso8601
    )

    message.publish

    # Give time for processing
    sleep(0.1)

    # Check that proc handler received the message
    assert_equal 1, received_messages.length
    assert_equal "PROC-001", received_messages[0][:id]
    assert_equal "Test proc integration", received_messages[0][:content]
    assert_equal "ProcHandlerIntegrationTest::IntegrationTestMessage", received_messages[0][:header_class]

    # Check that default handler also processed it
    assert_includes IntegrationTestMessage.default_processed, "PROC-001"
  end

  def test_multiple_proc_handlers_with_stdout_transport
    transport = SmartMessage::Transport::StdoutTransport.new(loopback: true)
    IntegrationTestMessage.transport transport
    IntegrationTestMessage.serializer SmartMessage::Serializer::JSON.new

    handler1_messages = []
    handler2_messages = []

    # Subscribe with two different procs
    handler1 = proc do |header, payload|
      data = JSON.parse(payload)
      handler1_messages << "H1:#{data['message_id']}"
    end

    handler2 = proc do |header, payload|
      data = JSON.parse(payload)
      handler2_messages << "H2:#{data['message_id']}"
    end

    id1 = IntegrationTestMessage.subscribe(handler1)
    id2 = IntegrationTestMessage.subscribe(handler2)

    # Verify different IDs
    refute_equal id1, id2

    # Publish a message
    message = IntegrationTestMessage.new(
      message_id: "MULTI-001",
      content: "Test multiple procs",
      timestamp: Time.now.iso8601
    )

    message.publish

    # Give time for processing
    sleep(0.1)

    # Both handlers should have received the message
    assert_equal ["H1:MULTI-001"], handler1_messages
    assert_equal ["H2:MULTI-001"], handler2_messages
  end

  def test_proc_handler_error_handling_integration
    IntegrationTestMessage.transport SmartMessage::Transport::MemoryTransport.new(auto_process: true)
    IntegrationTestMessage.serializer SmartMessage::Serializer::JSON.new

    error_handler_called = false
    success_handler_called = false

    # Subscribe with a proc that raises an error
    error_handler = proc do |header, payload|
      error_handler_called = true
      raise "Test error in proc handler"
    end

    # Subscribe with a proc that succeeds
    success_handler = proc do |header, payload|
      success_handler_called = true
    end

    IntegrationTestMessage.subscribe(error_handler)
    IntegrationTestMessage.subscribe(success_handler)

    # Publish a message
    message = IntegrationTestMessage.new(
      message_id: "ERROR-001",
      content: "Test error handling",
      timestamp: Time.now.iso8601
    )

    # This should not raise an exception at the top level
    begin
      message.publish
      sleep(0.1)  # Give time for processing
      # If we get here, no exception was raised at the top level
      assert true, "System handled proc handler error gracefully"
    rescue => e
      flunk "System crashed due to proc handler error: #{e.message}"
    end

    # Both handlers should have been called
    assert error_handler_called, "Error handler should have been called"
    assert success_handler_called, "Success handler should have been called"
  end

  def test_proc_handler_unsubscribe_integration
    IntegrationTestMessage.transport SmartMessage::Transport::MemoryTransport.new(auto_process: true)
    IntegrationTestMessage.serializer SmartMessage::Serializer::JSON.new

    call_count = 0

    # Subscribe with a proc
    test_proc = proc do |header, payload|
      call_count += 1
    end

    handler_id = IntegrationTestMessage.subscribe(test_proc)

    # Publish first message
    IntegrationTestMessage.new(
      message_id: "UNSUB-001",
      content: "Before unsubscribe",
      timestamp: Time.now.iso8601
    ).publish

    sleep(0.1)
    assert_equal 1, call_count

    # Unsubscribe the proc handler
    IntegrationTestMessage.unsubscribe(handler_id)

    # Verify the proc is removed from the registry
    refute SmartMessage::Base.proc_handler?(handler_id)

    # Publish second message
    IntegrationTestMessage.new(
      message_id: "UNSUB-002", 
      content: "After unsubscribe",
      timestamp: Time.now.iso8601
    ).publish

    sleep(0.1)

    # Call count should still be 1 (handler was unsubscribed)
    assert_equal 1, call_count
  end

  def test_mixed_handler_types_integration
    IntegrationTestMessage.transport SmartMessage::Transport::MemoryTransport.new(auto_process: true)
    IntegrationTestMessage.serializer SmartMessage::Serializer::JSON.new

    # Clear previous state
    IntegrationTestMessage.clear_default_processed

    results = []

    # 1. Default handler (already defined in class)
    IntegrationTestMessage.subscribe

    # 2. Block handler
    block_id = IntegrationTestMessage.subscribe do |header, payload|
      data = JSON.parse(payload)
      results << "BLOCK:#{data['message_id']}"
    end

    # 3. Proc handler
    test_proc = proc do |header, payload|
      data = JSON.parse(payload)
      results << "PROC:#{data['message_id']}"
    end
    proc_id = IntegrationTestMessage.subscribe(test_proc)

    # 4. Method handler

    TestService.clear_method_calls
    IntegrationTestMessage.subscribe("ProcHandlerIntegrationTest::TestService.handle_message")

    # Publish a message
    IntegrationTestMessage.new(
      message_id: "MIXED-001",
      content: "Test all handler types",
      timestamp: Time.now.iso8601
    ).publish

    sleep(0.1)

    # All handlers should have processed the message
    assert_includes IntegrationTestMessage.default_processed, "MIXED-001"
    assert_includes results, "BLOCK:MIXED-001"
    assert_includes results, "PROC:MIXED-001"
    assert_includes TestService.method_calls, "METHOD:MIXED-001"

    # Verify we have 4 different types of handlers
    assert_equal 1, IntegrationTestMessage.default_processed.count("MIXED-001")
    assert_equal 1, results.count("BLOCK:MIXED-001")
    assert_equal 1, results.count("PROC:MIXED-001")
    assert_equal 1, TestService.method_calls.count("METHOD:MIXED-001")
  end

  def test_lambda_vs_proc_integration
    IntegrationTestMessage.transport SmartMessage::Transport::MemoryTransport.new(auto_process: true)
    IntegrationTestMessage.serializer SmartMessage::Serializer::JSON.new

    proc_calls = []
    lambda_calls = []

    # Subscribe with a proc (flexible argument checking)
    test_proc = proc do |header, payload|
      proc_calls << "PROC_CALLED"
    end

    # Subscribe with a lambda (strict argument checking)
    test_lambda = lambda do |header, payload|
      lambda_calls << "LAMBDA_CALLED"
    end

    proc_id = IntegrationTestMessage.subscribe(test_proc)
    lambda_id = IntegrationTestMessage.subscribe(test_lambda)

    # Both should be proc handlers from the dispatcher's perspective
    assert SmartMessage::Base.proc_handler?(proc_id)
    assert SmartMessage::Base.proc_handler?(lambda_id)

    # Publish a message
    IntegrationTestMessage.new(
      message_id: "LAMBDA-001",
      content: "Test lambda vs proc",
      timestamp: Time.now.iso8601
    ).publish

    sleep(0.1)

    # Both should have been called
    assert_equal ["PROC_CALLED"], proc_calls
    assert_equal ["LAMBDA_CALLED"], lambda_calls
  end

  def test_concurrent_proc_handler_execution
    IntegrationTestMessage.transport SmartMessage::Transport::MemoryTransport.new(auto_process: true)
    IntegrationTestMessage.serializer SmartMessage::Serializer::JSON.new

    # Use a mutex to ensure thread safety in testing
    mutex = Mutex.new
    processing_order = []

    # Subscribe with multiple procs that have different processing times
    fast_proc = proc do |header, payload|
      mutex.synchronize { processing_order << "FAST_START" }
      sleep(0.01)  # Very quick
      mutex.synchronize { processing_order << "FAST_END" }
    end

    slow_proc = proc do |header, payload|
      mutex.synchronize { processing_order << "SLOW_START" }
      sleep(0.05)  # Slower
      mutex.synchronize { processing_order << "SLOW_END" }
    end

    IntegrationTestMessage.subscribe(fast_proc)
    IntegrationTestMessage.subscribe(slow_proc)

    # Publish message
    IntegrationTestMessage.new(
      message_id: "CONCURRENT-001",
      content: "Test concurrent execution",
      timestamp: Time.now.iso8601
    ).publish

    # Wait for both to complete
    sleep(0.1)

    # Both should have started and completed
    assert_includes processing_order, "FAST_START"
    assert_includes processing_order, "FAST_END"
    assert_includes processing_order, "SLOW_START"
    assert_includes processing_order, "SLOW_END"

    # Due to concurrent execution, fast handler should complete before slow handler
    fast_start_index = processing_order.index("FAST_START")
    fast_end_index = processing_order.index("FAST_END")
    slow_end_index = processing_order.index("SLOW_END")

    assert fast_start_index < fast_end_index, "Fast handler should start before it ends"
    assert fast_end_index < slow_end_index, "Fast handler should end before slow handler ends"
  end

end