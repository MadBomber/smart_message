# test/dead_letter_queue_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class DeadLetterQueueTest < Minitest::Test
  def setup
    @test_dlq_file = '/tmp/test_dlq.jsonl'
    @dlq = SmartMessage::DeadLetterQueue.new(@test_dlq_file)
    
    # Clean up any existing test file
    File.delete(@test_dlq_file) if File.exist?(@test_dlq_file)
    
    # Create a test message
    @header = create_header('test-123', 'TestMessage', from: 'test-service', to: 'target-service')
    @payload = '{"test": "data", "amount": 99.99}'
  end
  
  def teardown
    File.delete(@test_dlq_file) if File.exist?(@test_dlq_file)
  end
  
  def test_enqueue_message
    entry = @dlq.enqueue(@header, @payload, error: 'Test error', transport: 'redis')
    
    assert entry[:timestamp]
    assert_equal 'Test error', entry[:error]
    assert_equal 'redis', entry[:transport]
    assert_equal 1, @dlq.size
  end
  
  def test_dequeue_message
    # Enqueue a message first
    @dlq.enqueue(@header, @payload, error: 'Test error')
    
    # Dequeue and verify
    entry = @dlq.dequeue
    refute_nil entry
    assert_equal 'TestMessage', entry[:header][:message_class]
    assert_equal @payload, entry[:payload]
    assert_equal 'Test error', entry[:error]
    assert_equal 0, @dlq.size
  end
  
  def test_peek_message
    # Enqueue a message first
    @dlq.enqueue(@header, @payload, error: 'Test error')
    
    # Peek and verify message is still there
    entry = @dlq.peek
    refute_nil entry
    assert_equal 'TestMessage', entry[:header][:message_class]
    assert_equal 1, @dlq.size  # Message should still be in queue
  end
  
  def test_fifo_ordering
    # Enqueue multiple messages
    header1 = create_header('first', 'TestMessage')
    header2 = create_header('second', 'TestMessage')
    
    @dlq.enqueue(header1, '{"first": true}', error: 'First error')
    sleep(0.01)  # Ensure different timestamps
    @dlq.enqueue(header2, '{"second": true}', error: 'Second error')
    
    # Dequeue should return first message
    entry1 = @dlq.dequeue
    assert_equal 'first', entry1[:header][:uuid]
    
    entry2 = @dlq.dequeue
    assert_equal 'second', entry2[:header][:uuid]
  end
  
  def test_statistics
    # Enqueue messages of different types
    @dlq.enqueue(@header, @payload, error: 'Redis error')
    
    header2 = create_header('order-123', 'OrderMessage')
    @dlq.enqueue(header2, '{"order": 123}', error: 'Database error')
    
    header3 = create_header('test-456', 'TestMessage')
    @dlq.enqueue(header3, '{"test": "more"}', error: 'Redis error')
    
    stats = @dlq.statistics
    assert_equal 3, stats[:total]
    assert_equal 2, stats[:by_class]['TestMessage']
    assert_equal 1, stats[:by_class]['OrderMessage']
    assert_equal 2, stats[:by_error]['Redis error']
    assert_equal 1, stats[:by_error]['Database error']
  end
  
  def test_filter_by_class
    # Enqueue messages of different classes
    @dlq.enqueue(@header, @payload, error: 'Test error')
    
    order_header = create_header('order-456', 'OrderMessage')
    @dlq.enqueue(order_header, '{"order": 123}', error: 'Order error')
    
    # Filter should return only TestMessage entries
    test_entries = @dlq.filter_by_class('TestMessage')
    assert_equal 1, test_entries.size
    assert_equal 'TestMessage', test_entries[0][:header][:message_class]
    
    order_entries = @dlq.filter_by_class('OrderMessage')
    assert_equal 1, order_entries.size
    assert_equal 'OrderMessage', order_entries[0][:header][:message_class]
  end
  
  def test_filter_by_error_pattern
    @dlq.enqueue(@header, @payload, error: 'Redis connection timeout')
    
    header2 = create_header('order-789', 'OrderMessage')
    @dlq.enqueue(header2, '{"order": 123}', error: 'Database connection failed')
    
    # Filter by pattern
    redis_errors = @dlq.filter_by_error_pattern(/redis/i)
    assert_equal 1, redis_errors.size
    assert_match(/Redis/, redis_errors[0][:error])
    
    connection_errors = @dlq.filter_by_error_pattern('connection')
    assert_equal 2, connection_errors.size
  end
  
  def test_clear_queue
    @dlq.enqueue(@header, @payload, error: 'Test error')
    @dlq.enqueue(@header, @payload, error: 'Another error')
    
    assert_equal 2, @dlq.size
    
    @dlq.clear
    assert_equal 0, @dlq.size
  end
  
  def test_empty_queue_operations
    # Operations on empty queue should not crash
    assert_nil @dlq.dequeue
    assert_nil @dlq.peek
    assert_equal 0, @dlq.size
    assert_empty @dlq.inspect_messages
    
    stats = @dlq.statistics
    assert_equal 0, stats[:total]
  end
  
  def test_default_singleton
    # Test default singleton instance
    default_dlq = SmartMessage::DeadLetterQueue.default
    refute_nil default_dlq
    
    # Should return same instance
    assert_same default_dlq, SmartMessage::DeadLetterQueue.default
  end
  
  def test_export_range
    # Set up time ranges before enqueuing
    start_time = Time.now - 1  # Start from 1 second ago
    
    @dlq.enqueue(@header, @payload, error: 'Error 1')
    
    # Wait and set middle time
    sleep(0.1)
    middle_time = Time.now
    sleep(0.1)
    
    header2 = create_header('test-range-2', 'TestMessage')
    @dlq.enqueue(header2, '{"test": "data2"}', error: 'Error 2')
    
    end_time = Time.now + 1  # End 1 second from now
    
    # Export all messages
    all_messages = @dlq.export_range(start_time, end_time)
    assert_equal 2, all_messages.size
    
    # Test basic time range functionality (both messages should be in range)
    range_messages = @dlq.export_range(Time.now - 2, Time.now + 2)
    assert_equal 2, range_messages.size
  end
  
  private
  
  def create_header(uuid, message_class, **extra_attrs)
    SmartMessage::Header.new({
      uuid: uuid,
      message_class: message_class,
      published_at: Time.now,
      publisher_pid: Process.pid,
      from: 'test-service'
    }.merge(extra_attrs))
  end
end