# test/ddq_test.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/smart_message/ddq'

class DdqTest < Minitest::Test
  def setup
    @ddq_memory = SmartMessage::DDQ::Memory.new(3)
    
    # Only test Redis if it's available and properly configured
    begin
      # Test if Redis is available by pinging it
      require 'redis'
      redis_client = ::Redis.new(url: 'redis://localhost:6379', db: 15)
      redis_client.ping
      @ddq_redis = SmartMessage::DDQ::Redis.new(3, redis: redis_client)
    rescue => e
      @ddq_redis = nil
    end
  end
  
  def test_memory_ddq_basic_operations
    refute @ddq_memory.contains?("test-uuid-1")
    
    @ddq_memory.add("test-uuid-1")
    assert @ddq_memory.contains?("test-uuid-1")
    
    @ddq_memory.add("test-uuid-2")
    assert @ddq_memory.contains?("test-uuid-2")
    assert @ddq_memory.contains?("test-uuid-1")
  end
  
  def test_memory_ddq_circular_behavior
    # Fill beyond capacity
    @ddq_memory.add("uuid-1")
    @ddq_memory.add("uuid-2") 
    @ddq_memory.add("uuid-3")
    @ddq_memory.add("uuid-4")  # Should evict uuid-1
    
    refute @ddq_memory.contains?("uuid-1")  # Evicted
    assert @ddq_memory.contains?("uuid-2")
    assert @ddq_memory.contains?("uuid-3")
    assert @ddq_memory.contains?("uuid-4")
  end
  
  def test_memory_ddq_stats
    stats = @ddq_memory.stats
    assert_equal 3, stats[:size]
    assert_equal :memory, stats[:storage_type]
    assert_equal 0, stats[:current_count]
    
    @ddq_memory.add("uuid-1")
    stats = @ddq_memory.stats
    assert_equal 1, stats[:current_count]
  end
  
  def test_memory_ddq_clear
    @ddq_memory.add("uuid-1")
    @ddq_memory.add("uuid-2")
    assert_equal 2, @ddq_memory.stats[:current_count]
    
    @ddq_memory.clear
    assert_equal 0, @ddq_memory.stats[:current_count]
    refute @ddq_memory.contains?("uuid-1")
    refute @ddq_memory.contains?("uuid-2")
  end
  
  def test_redis_ddq_basic_operations
    skip "Redis not available" unless @ddq_redis
    
    refute @ddq_redis.contains?("test-uuid-1")
    
    @ddq_redis.add("test-uuid-1")
    assert @ddq_redis.contains?("test-uuid-1")
    
    @ddq_redis.clear
  end
  
  def test_ddq_factory_creation
    memory_ddq = SmartMessage::DDQ.create(:memory, 5)
    assert_instance_of SmartMessage::DDQ::Memory, memory_ddq
    assert_equal 5, memory_ddq.size
    
    assert_raises(ArgumentError) do
      SmartMessage::DDQ.create(:invalid_storage)
    end
  end
  
  def test_ddq_validation
    assert_raises(ArgumentError) do
      SmartMessage::DDQ::Memory.new(-1)
    end
    
    assert_raises(ArgumentError) do
      SmartMessage::DDQ::Memory.new("invalid")
    end
    
    ddq = SmartMessage::DDQ::Memory.new(5)
    assert_raises(ArgumentError) do
      ddq.contains?(nil)
    end
    
    assert_raises(ArgumentError) do
      ddq.add("")
    end
  end
end