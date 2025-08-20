# lib/smart_message/ddq/redis.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'base'

module SmartMessage
  module DDQ
    # Redis-based Deduplication Queue implementation
    # 
    # Uses Redis SET for O(1) lookup and LIST for circular queue behavior.
    # Supports distributed deduplication across multiple processes/servers.
    class Redis < Base
      attr_reader :redis, :key_prefix, :ttl
      
      def initialize(size, options = {})
        super(size)
        @redis = options[:redis] || default_redis_connection
        @key_prefix = options[:key_prefix] || 'smart_message:ddq'
        @ttl = options[:ttl] || 3600  # 1 hour default TTL
        
        validate_redis_connection!
        
        logger.debug { "[SmartMessage::DDQ::Redis] Initialized with size: #{@size}, TTL: #{@ttl}s" }
      end
      
      # Check if a UUID exists in the queue (O(1) operation)
      # @param uuid [String] The UUID to check
      # @return [Boolean] true if UUID exists, false otherwise
      def contains?(uuid)
        validate_uuid!(uuid)
        
        result = @redis.sismember(set_key, uuid)
        logger.debug { "[SmartMessage::DDQ::Redis] UUID #{uuid} exists: #{result}" }
        result
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error checking UUID #{uuid}: #{e.message}" }
        # Fail open - allow processing if Redis is down
        false
      end
      
      # Add a UUID to the queue, removing oldest if full (O(1) amortized)
      # @param uuid [String] The UUID to add
      # @return [void]
      def add(uuid)
        validate_uuid!(uuid)
        
        # Check if UUID already exists first (avoid unnecessary work)
        return if @redis.sismember(set_key, uuid)
        
        # Use Redis transaction for atomicity
        @redis.multi do |pipeline|
          # Add to set for O(1) lookup
          pipeline.sadd(set_key, uuid)
          
          # Add to list for ordering/eviction
          pipeline.lpush(list_key, uuid)
          
          # Trim list to maintain size (removes oldest)
          pipeline.ltrim(list_key, 0, @size - 1)
          
          # Set TTL on both keys
          pipeline.expire(set_key, @ttl)
          pipeline.expire(list_key, @ttl)
        end
        
        # Get and remove evicted items from set (outside transaction)
        list_length = @redis.llen(list_key)
        if list_length > @size
          evicted_uuids = @redis.lrange(list_key, @size, -1)
          evicted_uuids.each do |evicted_uuid|
            @redis.srem(set_key, evicted_uuid)
          end
        end
        
        logger.debug { "[SmartMessage::DDQ::Redis] Added UUID: #{uuid}" }
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error adding UUID #{uuid}: #{e.message}" }
        # Don't raise - deduplication failure shouldn't break message processing
      end
      
      # Get current queue statistics
      # @return [Hash] Statistics about the queue
      def stats
        set_size = @redis.scard(set_key)
        list_size = @redis.llen(list_key)
        
        super.merge(
          current_count: set_size,
          list_count: list_size,
          utilization: (set_size.to_f / @size * 100).round(2),
          ttl_remaining: @redis.ttl(set_key),
          redis_info: {
            host: redis_host,
            port: redis_port,
            db: redis_db
          }
        )
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error getting stats: #{e.message}" }
        super.merge(error: e.message)
      end
      
      # Clear all entries from the queue
      # @return [void]
      def clear
        @redis.multi do |pipeline|
          pipeline.del(set_key)
          pipeline.del(list_key)
        end
        
        logger.debug { "[SmartMessage::DDQ::Redis] Cleared all entries" }
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error clearing queue: #{e.message}" }
      end
      
      # Get the storage type identifier
      # @return [Symbol] Storage type
      def storage_type
        :redis
      end
      
      # Get current entries (for debugging/testing)
      # @return [Array<String>] Current UUIDs in insertion order (newest first)
      def entries
        @redis.lrange(list_key, 0, -1)
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error getting entries: #{e.message}" }
        []
      end
      
      private
      
      def set_key
        "#{@key_prefix}:set"
      end
      
      def list_key
        "#{@key_prefix}:list"
      end
      
      def default_redis_connection
        require 'redis'
        ::Redis.new
      rescue LoadError
        raise LoadError, "Redis gem not available. Install with: gem install redis"
      end
      
      def validate_redis_connection!
        @redis.ping
      rescue ::Redis::BaseError => e
        raise ConnectionError, "Failed to connect to Redis: #{e.message}"
      end
      
      def redis_host
        @redis.connection[:host] rescue 'unknown'
      end
      
      def redis_port
        @redis.connection[:port] rescue 'unknown'
      end
      
      def redis_db
        @redis.connection[:db] rescue 'unknown'
      end
    end
  end
end