# lib/smart_message/ddq/redis.rb
# encoding: utf-8
# frozen_string_literal: true

require 'redis'

module SmartMessage
  module DDQ
    # Redis-based Deduplication Queue implementation
    #
    # Each UUID is one Redis key written with SET NX EX, which makes
    # #reserve atomic across every process sharing the Redis server.  A UUID
    # is forgotten when its TTL runs out; +size+ is accepted for interface
    # compatibility but Redis storage is bounded by time, not by count.
    #
    # Options:
    #   redis:      a Redis client (default: Redis.new)
    #   key_prefix: namespace for the keys (default 'smart_message:ddq')
    #   ttl:        seconds a UUID is remembered (default 3600)
    #
    # When Redis is unreachable the queue fails open: #reserve answers true
    # and the error is logged, so messages are processed rather than lost.
    class Redis < Base
      DEFAULT_KEY_PREFIX = 'smart_message:ddq'
      DEFAULT_TTL        = 3600

      attr_reader :redis, :key_prefix, :ttl

      # @raise [SmartMessage::Errors::TransportError] when Redis cannot be reached
      def initialize(size, options = {})
        super(size)
        @redis      = options[:redis] || default_redis_connection
        @key_prefix = options[:key_prefix] || DEFAULT_KEY_PREFIX
        @ttl        = options[:ttl] || DEFAULT_TTL

        validate_redis_connection!
      end

      # (see Base#reserve)
      def reserve(uuid)
        validate_uuid!(uuid)
        @redis.set(key_for(uuid), 1, nx: true, ex: @ttl) ? true : false
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error reserving UUID #{uuid}: #{e.message}" }
        true # fail open
      end

      # (see Base#release)
      def release(uuid)
        validate_uuid!(uuid)
        @redis.del(key_for(uuid))
        nil
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error releasing UUID #{uuid}: #{e.message}" }
        nil
      end

      # Check if a UUID exists in the queue
      def contains?(uuid)
        validate_uuid!(uuid)
        @redis.exists?(key_for(uuid))
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error checking UUID #{uuid}: #{e.message}" }
        false # fail open
      end

      # Get current queue statistics
      # @return [Hash] Statistics about the queue
      def stats
        super.merge(current_count: entries.size, ttl: @ttl, key_prefix: @key_prefix)
      end

      # Clear all entries from the queue
      def clear
        keys = scan_keys
        @redis.del(*keys) unless keys.empty?
        nil
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error clearing queue: #{e.message}" }
        nil
      end

      def storage_type
        :redis
      end

      # Get current entries (for debugging/testing)
      # @return [Array<String>] Current UUIDs, in no particular order
      def entries
        scan_keys.map { |key| key.delete_prefix("#{@key_prefix}:") }
      rescue ::Redis::BaseError => e
        logger.error { "[SmartMessage::DDQ::Redis] Error getting entries: #{e.message}" }
        []
      end

      private

      def key_for(uuid)
        "#{@key_prefix}:#{uuid}"
      end

      def scan_keys
        @redis.scan_each(match: "#{@key_prefix}:*").to_a
      end

      def default_redis_connection
        ::Redis.new
      end

      def validate_redis_connection!
        @redis.ping
      rescue ::Redis::BaseError => e
        raise SmartMessage::Errors::TransportError, "DDQ cannot connect to Redis: #{e.message}"
      end
    end
  end
end
