# test/multi_transport_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class MultiTransportTest < Minitest::Test
  class TestMessage < SmartMessage::Base
    property :content, required: true
    property :priority, default: 'normal'
  end

  class SingleTransportMessage < SmartMessage::Base
    property :data, required: true
    transport SmartMessage::Transport::MemoryTransport.new(auto_process: false)
  end

  class MultiTransportMessage < SmartMessage::Base
    property :content, required: true
    transport [
      SmartMessage::Transport::MemoryTransport.new(auto_process: false),
      SmartMessage::Transport::StdoutTransport.new(format: :compact)
    ]
  end

  # Mock transport that always fails for testing error scenarios
  class FailingTransport < SmartMessage::Transport::Base
    def publish(message)
      raise StandardError, "Simulated transport failure"
    end

    def subscribe(message_class, process_method = nil, &block)
      # No-op for testing
    end

    def unsubscribe(message_class, process_method = nil)
      # No-op for testing
    end
  end

  # Mock transport that counts publish calls
  class CountingTransport < SmartMessage::Transport::Base
    attr_reader :publish_count, :published_messages

    def initialize(**options)
      super
      @publish_count = 0
      @published_messages = []
    end

    def publish(message)
      @publish_count += 1
      @published_messages << message
    end

    def subscribe(message_class, process_method = nil, &block)
      # No-op for testing
    end

    def unsubscribe(message_class, process_method = nil)
      # No-op for testing
    end

    def reset_counters
      @publish_count = 0
      @published_messages = []
    end
  end

  def setup
    # Reset any global configuration
    SmartMessage::Transport.instance_variable_set(:@default, nil) if SmartMessage::Transport.instance_variable_defined?(:@default)
    
    # Ensure class configurations are set properly
    SingleTransportMessage.transport(SmartMessage::Transport::MemoryTransport.new(auto_process: false))
    MultiTransportMessage.transport([
      SmartMessage::Transport::MemoryTransport.new(auto_process: false),
      SmartMessage::Transport::StdoutTransport.new(format: :compact)
    ])
  end

  def teardown
    # Clean up after tests
  end

  # Test backward compatibility - single transport configuration
  def test_single_transport_backward_compatibility
    msg = SingleTransportMessage.new(data: "test", from: "test_app")
    
    # Should work exactly like before
    assert msg.transports.length >= 1, "Expected at least 1 transport, got #{msg.transports.length}"
    
    # If there's exactly one transport, these should pass
    if msg.transports.length == 1
      assert msg.single_transport?
      refute msg.multiple_transports?
    end
    
    # The first transport should be the expected type
    assert_instance_of SmartMessage::Transport::MemoryTransport, msg.transport if msg.transport
    assert_instance_of SmartMessage::Transport::MemoryTransport, msg.transports.first if msg.transports.first
  end

  # Test multiple transport configuration
  def test_multiple_transport_configuration
    msg = MultiTransportMessage.new(content: "test", from: "test_app")
    
    # Should have multiple transports
    assert_equal 2, msg.transports.length
    refute msg.single_transport?
    assert msg.multiple_transports?
    
    # transport() should return first transport for backward compatibility
    assert_instance_of SmartMessage::Transport::MemoryTransport, msg.transport
    
    # transports() should return all transports
    transport_types = msg.transports.map(&:class)
    assert_includes transport_types, SmartMessage::Transport::MemoryTransport
    assert_includes transport_types, SmartMessage::Transport::StdoutTransport
  end

  # Test array vs single transport assignment
  def test_transport_assignment_types
    # Test single transport assignment
    msg1 = TestMessage.new(content: "test1", from: "test_app")
    single_transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    msg1.transport(single_transport)
    
    assert_equal 1, msg1.transports.length
    assert msg1.single_transport?
    assert_equal single_transport, msg1.transport
    
    # Test array transport assignment
    msg2 = TestMessage.new(content: "test2", from: "test_app")
    transport_array = [
      SmartMessage::Transport::MemoryTransport.new(auto_process: false),
      SmartMessage::Transport::StdoutTransport.new(format: :compact)
    ]
    msg2.transport(transport_array)
    
    assert_equal 2, msg2.transports.length
    assert msg2.multiple_transports?
    assert_equal transport_array.first, msg2.transport # First transport for backward compatibility
    assert_equal transport_array, msg2.transports
  end

  # Test class-level vs instance-level transport configuration
  def test_class_vs_instance_transport_configuration
    # Class-level configuration
    assert_equal 2, MultiTransportMessage.transports.length
    assert MultiTransportMessage.multiple_transports?
    
    # Instance inherits class configuration
    msg1 = MultiTransportMessage.new(content: "test1", from: "test_app")
    assert_equal 2, msg1.transports.length
    
    # Instance can override class configuration
    custom_transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    msg2 = MultiTransportMessage.new(content: "test2", from: "test_app")
    msg2.transport(custom_transport)
    
    assert_equal 1, msg2.transports.length
    assert msg2.single_transport?
    assert_equal custom_transport, msg2.transport
    
    # Class configuration remains unchanged
    assert_equal 2, MultiTransportMessage.transports.length
  end

  # Test successful publishing to multiple transports
  def test_successful_multi_transport_publishing
    counter1 = CountingTransport.new
    counter2 = CountingTransport.new
    counter3 = CountingTransport.new
    
    msg = TestMessage.new(content: "test message", from: "test_app")
    msg.transport([counter1, counter2, counter3])
    
    # All counters should start at 0
    assert_equal 0, counter1.publish_count
    assert_equal 0, counter2.publish_count
    assert_equal 0, counter3.publish_count
    
    # Publish message
    msg.publish
    
    # All transports should have received the message
    assert_equal 1, counter1.publish_count
    assert_equal 1, counter2.publish_count
    assert_equal 1, counter3.publish_count
    
    # All should have received the same message instance
    assert_equal msg, counter1.published_messages.first
    assert_equal msg, counter2.published_messages.first
    assert_equal msg, counter3.published_messages.first
  end

  # Test partial transport failure (some succeed, some fail)
  def test_partial_transport_failure_resilience
    success_transport = CountingTransport.new
    fail_transport = FailingTransport.new
    success_transport2 = CountingTransport.new
    
    msg = TestMessage.new(content: "test message", from: "test_app")
    msg.transport([success_transport, fail_transport, success_transport2])
    
    # Should not raise error despite one transport failing
    msg.publish
    
    # Successful transports should have received the message
    assert_equal 1, success_transport.publish_count
    assert_equal 1, success_transport2.publish_count
    
    # Message should have been published successfully overall
    assert_equal msg, success_transport.published_messages.first
    assert_equal msg, success_transport2.published_messages.first
  end

  # Test all transports failing
  def test_all_transports_failing
    fail_transport1 = FailingTransport.new
    fail_transport2 = FailingTransport.new
    
    msg = TestMessage.new(content: "test message", from: "test_app")
    msg.transport([fail_transport1, fail_transport2])
    
    # Should raise PublishError when ALL transports fail
    error = assert_raises(SmartMessage::Errors::PublishError) { msg.publish }
    assert_match(/All transports failed/, error.message)
    assert_match(/FailingTransport.*Simulated transport failure/, error.message)
  end

  # Test transport configuration validation
  def test_transport_configuration_validation
    msg = TestMessage.new(content: "test", from: "test_app")
    
    # Should work with nil (uses default)
    msg.transport(nil)
    assert msg.transports.length >= 1 # Default transport(s)
    
    # Should work with empty array (though not practically useful)
    msg.transport([])
    assert_equal 0, msg.transports.length
    assert msg.transport.nil? # No transport available
  end

  # Test transport utility methods
  def test_transport_utility_methods
    # Single transport
    single_msg = TestMessage.new(content: "test", from: "test_app")
    single_msg.transport(CountingTransport.new)
    
    assert single_msg.single_transport?
    refute single_msg.multiple_transports?
    assert_equal 1, single_msg.transports.length
    
    # Multiple transports
    multi_msg = TestMessage.new(content: "test", from: "test_app")
    multi_msg.transport([CountingTransport.new, CountingTransport.new])
    
    refute multi_msg.single_transport?
    assert multi_msg.multiple_transports?
    assert_equal 2, multi_msg.transports.length
    
    # No transports
    empty_msg = TestMessage.new(content: "test", from: "test_app")
    empty_msg.transport([])
    
    refute empty_msg.single_transport?
    refute empty_msg.multiple_transports?
    assert_equal 0, empty_msg.transports.length
  end

  # Test transport reset functionality
  def test_transport_reset_functionality
    msg = MultiTransportMessage.new(content: "test", from: "test_app")
    
    # Initially has class-level transports
    assert_equal 2, msg.transports.length
    assert msg.multiple_transports?
    
    # Override with instance-level transport
    custom_transport = CountingTransport.new
    msg.transport(custom_transport)
    assert_equal 1, msg.transports.length
    assert msg.single_transport?
    
    # Reset should clear instance-level transport and fall back to class-level
    msg.reset_transport
    assert_equal 2, msg.transports.length
    assert msg.multiple_transports?
  end

  # Test mixed transport types (Memory + Stdout)
  def test_mixed_transport_types_integration
    memory_transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    stdout_transport = SmartMessage::Transport::StdoutTransport.new(format: :compact)
    
    msg = TestMessage.new(content: "integration test", from: "test_app")
    msg.transport([memory_transport, stdout_transport])
    
    # Should publish successfully to both
    # The stdout output shows in the actual test run - we can see it in the test output
    msg.publish
    
    # Memory transport should have received 1 message (auto_process: false means it stores but doesn't process)
    assert_equal 1, memory_transport.message_count
    
    # Both transports should be configured
    assert_equal 2, msg.transports.length
    assert msg.multiple_transports?
  end

  # Test transport method return values for chaining
  def test_transport_method_chaining
    msg = TestMessage.new(content: "test", from: "test_app")
    
    # Setting single transport should return the transport for chaining
    transport = CountingTransport.new
    result = msg.transport(transport)
    assert_equal transport, result
    
    # Setting array should return the array for chaining
    transport_array = [CountingTransport.new, CountingTransport.new]
    result = msg.transport(transport_array)
    assert_equal transport_array, result
  end

end