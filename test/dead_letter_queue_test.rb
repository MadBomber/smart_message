# test/dead_letter_queue_test.rb
# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require_relative 'test_helper'

class DeadLetterQueueTest < Minitest::Test
  class TestMessage < SmartMessage::Base
    property :test_data, required: true
    property :amount
  end
  
  class OrderMessage < SmartMessage::Base
    property :order_id, required: true
    property :amount
  end
  def setup
    @test_dlq_file = temp_path('test_dlq.jsonl')
    @dlq = SmartMessage::DeadLetterQueue.new(@test_dlq_file)
    
    # Clean up any existing test file
    File.delete(@test_dlq_file) if File.exist?(@test_dlq_file)
    
    # Configure message classes
    TestMessage.config do
      # Using default transport serialization
    end
    
    OrderMessage.config do
      # Using default transport serialization
    end
    
    @message = TestMessage.new(
      test_data: 'sample data',
      amount: 99.99,
      from: 'test-service',
      to: 'target-service'
    )
    
  end
  
  def teardown
    File.delete(@test_dlq_file) if File.exist?(@test_dlq_file)
  end
  
  def test_enqueue_message
    entry = @dlq.enqueue(@message, error: 'Test error', transport: 'redis')
    
    assert entry[:timestamp]
    assert_equal 'Test error', entry[:error]
    assert_equal 'redis', entry[:transport]
    assert_equal 1, @dlq.size
  end
  
  def test_dequeue_message
    # Enqueue a message first
    @dlq.enqueue(@message, error: 'Test error')
    
    # Dequeue and verify
    entry = @dlq.dequeue
    refute_nil entry
    assert_equal 'DeadLetterQueueTest::TestMessage', entry[:header][:message_class]
    payload = JSON.parse(entry[:payload], symbolize_names: true)
    assert_equal 'sample data', payload[:test_data]
    assert_equal @message.uuid, payload[:_sm_header][:uuid]
    assert_equal 'Test error', entry[:error]
    assert_equal 0, @dlq.size
  end
  
  def test_peek_message
    # Enqueue a message first
    # Using @message with flat structure
    @dlq.enqueue(@message, error: 'Test error')
    
    # Peek and verify message is still there
    entry = @dlq.peek
    refute_nil entry
    assert_equal 'DeadLetterQueueTest::TestMessage', entry[:header][:message_class]
    assert_equal 1, @dlq.size  # Message should still be in queue
  end
  
  def test_fifo_ordering
    # Enqueue multiple messages
    message1 = create_test_message('first message')
    message2 = create_test_message('second message')
    
    @dlq.enqueue(message1, error: 'First error')
    sleep(0.01)  # Ensure different timestamps
    @dlq.enqueue(message2, error: 'Second error')
    
    # Dequeue should return first message
    entry1 = @dlq.dequeue
    assert_equal 'First error', entry1[:error]
    
    entry2 = @dlq.dequeue
    assert_equal 'Second error', entry2[:error]
  end
  
  def test_statistics
    # Enqueue messages of different types
    # Using @message with flat structure
    @dlq.enqueue(@message, error: 'Redis error')
    
    order_message = create_order_message('order-123')
    @dlq.enqueue(order_message, error: 'Database error')
    
    test_message2 = create_test_message('more test data')
    @dlq.enqueue(test_message2, error: 'Redis error')
    
    stats = @dlq.statistics
    assert_equal 3, stats[:total]
    assert_equal 2, stats[:by_class]['TestMessage']
    assert_equal 1, stats[:by_class]['OrderMessage']
    assert_equal 2, stats[:by_error]['Redis error']
    assert_equal 1, stats[:by_error]['Database error']
  end
  
  def test_filter_by_class
    # Enqueue messages of different classes
    # Using @message with flat structure
    @dlq.enqueue(@message, error: 'Test error')
    
    order_message = create_order_message('order-456')
    @dlq.enqueue(order_message, error: 'Order error')
    
    # Filter should return only TestMessage entries
    test_entries = @dlq.filter_by_class('DeadLetterQueueTest::TestMessage')
    assert_equal 1, test_entries.size
    assert_equal 'DeadLetterQueueTest::TestMessage', test_entries[0][:header][:message_class]
    
    order_entries = @dlq.filter_by_class('DeadLetterQueueTest::OrderMessage')
    assert_equal 1, order_entries.size
    assert_equal 'DeadLetterQueueTest::OrderMessage', order_entries[0][:header][:message_class]
  end
  
  def test_filter_by_error_pattern
    # Using @message with flat structure
    @dlq.enqueue(@message, error: 'Redis connection timeout')
    
    order_message2 = create_order_message('order-789')
    @dlq.enqueue(order_message2, error: 'Database connection failed')
    
    # Filter by pattern
    redis_errors = @dlq.filter_by_error_pattern(/redis/i)
    assert_equal 1, redis_errors.size
    assert_match(/Redis/, redis_errors[0][:error])
    
    connection_errors = @dlq.filter_by_error_pattern('connection')
    assert_equal 2, connection_errors.size
  end
  
  def test_clear_queue
    # Using @message with flat structure
    @dlq.enqueue(@message, error: 'Test error')
    @dlq.enqueue(@message, error: 'Another error')
    
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
  
  def test_inspect_messages_returns_first_limit_entries
    Dir.mktmpdir do |dir|
      dlq = SmartMessage::DeadLetterQueue.new(File.join(dir, 'dlq.jsonl'))
      5.times { |i| dlq.enqueue(@message, error: "error #{i}") }

      errors = dlq.inspect_messages(limit: 3).map { |entry| entry[:error] }

      assert_equal ['error 0', 'error 1', 'error 2'], errors
      assert_equal 5, dlq.size
    end
  end

  def test_inspect_messages_returns_all_entries_under_limit
    Dir.mktmpdir do |dir|
      dlq = SmartMessage::DeadLetterQueue.new(File.join(dir, 'dlq.jsonl'))
      2.times { |i| dlq.enqueue(@message, error: "error #{i}") }

      assert_equal 2, dlq.inspect_messages(limit: 3).size
    end
  end

  def test_inspect_messages_with_non_positive_limit_returns_empty
    Dir.mktmpdir do |dir|
      dlq = SmartMessage::DeadLetterQueue.new(File.join(dir, 'dlq.jsonl'))
      dlq.enqueue(@message, error: 'error')

      assert_empty dlq.inspect_messages(limit: 0)
      assert_empty dlq.inspect_messages(limit: -1)
    end
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
    
    # Using @message with flat structure
    @dlq.enqueue(@message, error: 'Error 1')
    
    # Wait and set middle time
    sleep(0.3)
    _middle_time = Time.now
    sleep(0.3)
    
    test_message2 = create_test_message('data2')
    @dlq.enqueue(test_message2, error: 'Error 2')
    
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
  
  def create_test_message(data, **extra_attrs)
    attrs = {
      test_data: data,
      amount: 99.99,
      from: 'test-service'
    }.merge(extra_attrs)
    TestMessage.new(**attrs)
  end
  
  def create_order_message(order_id, **extra_attrs)
    attrs = {
      order_id: order_id,
      amount: 123.45,
      from: 'order-service'
    }.merge(extra_attrs)
    OrderMessage.new(**attrs)
  end

  # Store an encoded OrderMessage as a raw entry received for +stored_as+
  def enqueue_raw_order(stored_as:)
    payload = SmartMessage::Envelope.encode(create_order_message("ORD-1"), SmartMessage::Serializer::Json.new)
    @dlq.enqueue_raw(message_class: stored_as, payload: payload, error_info: { error: "could not be received" })
  end

  public

  # ---- queue safety (review finding R6) ---------------------------------

  def test_concurrent_enqueue_and_dequeue_lose_nothing
    writers = 8.times.map do
      Thread.new { 25.times { |i| @dlq.enqueue(@message, error: "error #{i}") } }
    end
    taken   = Queue.new
    readers = 4.times.map do
      Thread.new { 25.times { (entry = @dlq.dequeue) && taken << entry } }
    end
    (writers + readers).each(&:join)

    assert_equal 200, taken.size + @dlq.size, "every enqueued entry is either dequeued or still queued"
    assert_equal taken.size, Array.new(taken.size) { taken.pop[:id] }.uniq.size, "no entry is dequeued twice"
  end

  def test_two_queue_objects_on_one_file_share_it_safely
    other = SmartMessage::DeadLetterQueue.new(@test_dlq_file)

    threads = [@dlq, other].map do |queue|
      Thread.new { 50.times { queue.enqueue(@message, error: "shared") } }
    end
    threads.each(&:join)

    assert_equal 100, @dlq.size
    assert_equal 100, @dlq.entries.size, "no line was torn by a concurrent write"
  end

  def test_corrupt_first_line_does_not_wedge_the_queue
    File.write(@test_dlq_file, "this is not json\n")
    @dlq.enqueue(@message, error: "after the corrupt line")

    assert_equal "after the corrupt line", @dlq.peek[:error]

    entry = @dlq.dequeue

    assert_equal "after the corrupt line", entry[:error]
    assert_equal 0, @dlq.size, "the corrupt line is dropped along the way"
    assert_nil @dlq.dequeue
  end

  def test_statistics_report_corrupt_lines
    @dlq.enqueue(@message, error: "ok")
    File.open(@test_dlq_file, "a") { |file| file.puts("{broken") }

    stats = @dlq.statistics

    assert_equal 1, stats[:total]
    assert_equal 1, stats[:corrupt]
  end

  def test_failed_replay_keeps_the_entry_and_counts_the_retry
    @dlq.enqueue(@message, error: "original failure")

    result = @dlq.replay_one(FailingTransport.new)

    refute result[:success]
    assert_equal 1, @dlq.size, "a failed replay must not lose the entry"
    entry = @dlq.peek
    assert_equal 1, entry[:retry_count]
    assert_match(/Replay failed/, entry[:error])
  end

  def test_replay_all_stops_after_one_pass_when_every_replay_fails
    3.times { @dlq.enqueue(@message, error: "original failure") }

    results = @dlq.replay_all(FailingTransport.new)

    assert_equal 0, results[:success]
    assert_equal 3, results[:failed]
    assert_equal 3, @dlq.size
    assert_equal [1, 1, 1], @dlq.entries.map { |entry| entry[:retry_count] }
  end

  def test_failed_replay_from_the_default_queue_does_not_add_a_copy
    dlq.enqueue(@message, error: "original failure")

    3.times { refute dlq.replay_one(FailingTransport.new)[:success] }

    assert_equal 1, dlq.size, "the entry is kept once, however often its replay fails"
    assert_equal 3, dlq.peek[:retry_count]
  end

  def test_replay_uses_the_class_transport_when_none_is_given
    transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    @message.class.transport(transport)
    @dlq.enqueue(@message, error: "original failure")

    assert @dlq.replay_one[:success]
    assert_equal 1, transport.message_count
    assert @dlq.empty?
  ensure
    @message.class.reset_transport
  end

  def test_successful_replay_removes_only_that_entry_and_keeps_the_uuid
    first  = @dlq.enqueue(@message, error: "first")
    second = @dlq.enqueue(@message, error: "second")
    transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)

    result = @dlq.replay_one(transport)

    assert result[:success]
    assert_equal @message.uuid, result[:message].uuid, "a replayed message keeps its identity"
    assert_equal [second[:id]], @dlq.entries.map { |entry| entry[:id] }
    refute_equal first[:id], second[:id]
    assert_equal 1, transport.message_count
  end

  def test_enqueue_raw_stores_an_undecodable_payload
    entry = @dlq.enqueue_raw(
      message_class: "DeadLetterQueueTest::TestMessage",
      payload:       "not json at all",
      error_info:    { error: "DecodeError: bad payload", transport: "SmartMessage::Transport::RedisTransport" }
    )

    assert_equal "not json at all", @dlq.peek[:payload]
    assert_equal "DeadLetterQueueTest::TestMessage", entry[:header][:message_class]

    result = @dlq.replay_one(SmartMessage::Transport::MemoryTransport.new)

    refute result[:success], "an undecodable payload cannot be replayed"
    assert_equal 1, @dlq.size, "and it stays in the queue"
  end

  def test_replay_rebuilds_a_raw_entry_only_as_the_class_it_was_stored_for
    enqueue_raw_order(stored_as: TestMessage.name)
    transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    OrderMessage.transport(transport)

    results = @dlq.replay_all

    assert_equal 0, results[:success]
    assert_equal 1, results[:failed]
    assert_match(/MessageClassMismatch/, results[:errors].first)
    assert_equal 0, transport.message_count, "the payload is not published as #{OrderMessage}"
    assert_equal 1, @dlq.size, "the entry stays in the queue"
  ensure
    OrderMessage.reset_transport
  end

  def test_replay_of_a_raw_entry_stored_without_a_class_uses_the_payload_header
    [SmartMessage::DeadLetterQueue::UNKNOWN_CLASS, nil].each do |stored_as|
      @dlq.clear
      entry = enqueue_raw_order(stored_as: stored_as)

      result = @dlq.replay_one(SmartMessage::Transport::MemoryTransport.new(auto_process: false))

      assert_equal SmartMessage::DeadLetterQueue::UNKNOWN_CLASS, entry[:header][:message_class]
      assert result[:success], "stored as #{stored_as.inspect}: #{result[:error]}"
      assert_instance_of OrderMessage, result[:message]
      assert @dlq.empty?
    end
  end

  def test_replay_of_a_raw_entry_stored_for_a_blank_channel_fails
    ["", " "].each do |stored_as|
      @dlq.clear
      enqueue_raw_order(stored_as: stored_as)

      result = @dlq.replay_one(SmartMessage::Transport::MemoryTransport.new(auto_process: false))

      refute result[:success], "stored as #{stored_as.inspect}"
      assert_match(/MessageClassMismatch/, result[:error])
    end
  end

  def test_replay_of_an_entry_whose_header_names_no_class_uses_the_payload_header
    entry = enqueue_raw_order(stored_as: OrderMessage.name)
    [{}, "not a header"].each do |header|
      File.write(@test_dlq_file, "#{JSON.generate(entry.merge(header: header))}\n")

      result = @dlq.replay_one(SmartMessage::Transport::MemoryTransport.new(auto_process: false))

      assert result[:success], "header #{header.inspect}: #{result[:error]}"
      assert @dlq.empty?
    end
    File.write(@test_dlq_file, "#{JSON.generate(entry.except(:header))}\n")
    assert @dlq.replay_one(SmartMessage::Transport::MemoryTransport.new(auto_process: false))[:success]
  end

  def test_default_path_is_absolute_and_not_in_the_working_directory
    path = SmartMessage::Configuration.default_dlq_path({})

    assert_equal File.expand_path(path), path
    refute path.start_with?(Dir.pwd + File::SEPARATOR)
  end

  def test_default_path_honours_the_environment
    assert_equal "/var/tmp/app/dlq.jsonl",
                 SmartMessage::Configuration.default_dlq_path("SMART_MESSAGE_DLQ_PATH" => "/var/tmp/app/dlq.jsonl")
    assert_equal "/state/smart_message/dead_letters.jsonl",
                 SmartMessage::Configuration.default_dlq_path("XDG_STATE_HOME" => "/state")
  end

  def test_default_queue_follows_the_configured_path
    path = temp_path("configured_dlq.jsonl")
    SmartMessage.configure { |config| config.dlq_path = path }

    assert_equal path, SmartMessage::DeadLetterQueue.default.file_path
    assert_same SmartMessage::DeadLetterQueue.default, SmartMessage::DeadLetterQueue.default
  end

  # A transport whose publish always fails
  class FailingTransport < SmartMessage::Transport::Base
    def do_publish(_message_class, _serialized_message)
      raise IOError, "transport is down"
    end
  end
end
