# test/deduplication_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class DeduplicationTest < Minitest::Test
  class TestDedupMessage < SmartMessage::Base
    version 1
    property :content, required: true
    
    from "test-service"
    
    ddq_size 5
    ddq_storage :memory
    enable_deduplication!
    
    def self.process(message)
      @@processed_messages ||= []
      @@processed_messages << message.uuid
    end
    
    def self.processed_messages
      @@processed_messages || []
    end
    
    def self.clear_processed
      @@processed_messages = []
    end
  end
  
  class TestNormalMessage < SmartMessage::Base
    version 1
    property :content, required: true
    
    from "test-service"
    
    def self.process(message)
      @@processed_messages ||= []
      @@processed_messages << message.uuid
    end
    
    def self.processed_messages
      @@processed_messages || []
    end
    
    def self.clear_processed
      @@processed_messages = []
    end
  end
  
  def setup
    TestDedupMessage.clear_ddq!
    TestDedupMessage.clear_processed
    TestNormalMessage.clear_processed
  end
  
  def test_deduplication_configuration
    assert TestDedupMessage.ddq_enabled?
    refute TestNormalMessage.ddq_enabled?
    
    config = TestDedupMessage.ddq_config
    assert config[:enabled]
    assert_equal 5, config[:size]
    assert_equal :memory, config[:storage]
  end
  
  def test_deduplication_instance_methods
    message = TestDedupMessage.new(content: "test")
    refute message.duplicate?
    
    # Mark as processed
    message.mark_as_processed!
    
    # Create same message again (different instance, same UUID won't work)
    # So let's create a message with a known UUID
    header = SmartMessage::Header.new(
      uuid: "test-uuid-123",
      message_class: "DeduplicationTest::TestDedupMessage",
      published_at: Time.now,
      publisher_pid: Process.pid,
      version: 1,
      from: "test-service"
    )
    
    dup_message = TestDedupMessage.new(
      _sm_header: header,
      _sm_payload: { content: "test content" }
    )
    
    # First time should not be duplicate
    refute dup_message.duplicate?
    dup_message.mark_as_processed!
    
    # Second message with same UUID should be duplicate
    dup_message2 = TestDedupMessage.new(
      _sm_header: header,
      _sm_payload: { content: "different content" }
    )
    assert dup_message2.duplicate?
  end
  
  def test_dispatcher_deduplication_integration
    TestDedupMessage.transport(SmartMessage::Transport::MemoryTransport.new)
    TestDedupMessage.serializer(SmartMessage::Serializer::Json.new)
    TestDedupMessage.subscribe('DeduplicationTest::TestDedupMessage.process')
    
    # Create message with specific UUID
    header = SmartMessage::Header.new(
      uuid: "dedup-test-uuid",
      message_class: "DeduplicationTest::TestDedupMessage", 
      published_at: Time.now,
      publisher_pid: Process.pid,
      version: 1,
      from: "test-service"
    )
    
    message = TestDedupMessage.new(
      _sm_header: header,
      _sm_payload: { content: "test message" }
    )
    
    # First publish should process
    message.publish
    sleep 0.1  # Allow async processing
    
    assert_equal 1, TestDedupMessage.processed_messages.length
    assert_includes TestDedupMessage.processed_messages, "dedup-test-uuid"
    
    # Second publish with same UUID should be skipped
    message2 = TestDedupMessage.new(
      _sm_header: header,
      _sm_payload: { content: "duplicate message" }
    )
    
    message2.publish
    sleep 0.1  # Allow async processing
    
    # Should still only have 1 processed message
    assert_equal 1, TestDedupMessage.processed_messages.length
  end
  
  def test_normal_message_without_deduplication
    TestNormalMessage.transport(SmartMessage::Transport::MemoryTransport.new)
    TestNormalMessage.serializer(SmartMessage::Serializer::Json.new)
    TestNormalMessage.subscribe('DeduplicationTest::TestNormalMessage.process')
    
    # Create messages with same UUID (simulating duplicates)
    header = SmartMessage::Header.new(
      uuid: "normal-test-uuid",
      message_class: "DeduplicationTest::TestNormalMessage",
      published_at: Time.now,
      publisher_pid: Process.pid,
      version: 1,
      from: "test-service"
    )
    
    message1 = TestNormalMessage.new(
      _sm_header: header,
      _sm_payload: { content: "test message 1" }
    )
    
    message2 = TestNormalMessage.new(
      _sm_header: header,
      _sm_payload: { content: "test message 2" }
    )
    
    # Both should process since deduplication is disabled
    message1.publish
    sleep 0.1
    message2.publish
    sleep 0.1
    
    assert_equal 2, TestNormalMessage.processed_messages.length
  end
  
  def test_ddq_stats
    stats = TestDedupMessage.ddq_stats
    assert stats[:enabled]
    assert_equal 0, stats[:current_count]
    
    # Add some UUIDs
    TestDedupMessage.get_ddq_instance.add("uuid-1")
    TestDedupMessage.get_ddq_instance.add("uuid-2")
    
    stats = TestDedupMessage.ddq_stats
    assert_equal 2, stats[:current_count]
  end
  
  def test_class_level_duplicate_check
    refute TestDedupMessage.duplicate_uuid?("unknown-uuid")
    
    TestDedupMessage.get_ddq_instance.add("known-uuid")
    assert TestDedupMessage.duplicate_uuid?("known-uuid")
  end
  
  private
  
  # Helper method to access private method for testing
  def get_ddq_instance_for(klass)
    klass.send(:get_ddq_instance)
  end
end