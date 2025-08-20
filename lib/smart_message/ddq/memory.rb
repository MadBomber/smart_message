# lib/smart_message/ddq/memory.rb
# encoding: utf-8
# frozen_string_literal: true

require 'set'
require_relative 'base'

module SmartMessage
  module DDQ
    # Memory-based Deduplication Queue implementation
    # 
    # Uses a hybrid approach with Array for circular queue behavior 
    # and Set for O(1) lookup performance. Thread-safe with Mutex protection.
    class Memory < Base
      def initialize(size)
        super(size)
        @circular_array = Array.new(@size)
        @lookup_set = Set.new
        @index = 0
        @mutex = Mutex.new
        @count = 0
        
        logger.debug { "[SmartMessage::DDQ::Memory] Initialized with size: #{@size}" }
      end
      
      # Check if a UUID exists in the queue (O(1) operation)
      # @param uuid [String] The UUID to check
      # @return [Boolean] true if UUID exists, false otherwise
      def contains?(uuid)
        validate_uuid!(uuid)
        
        @mutex.synchronize do
          @lookup_set.include?(uuid)
        end
      end
      
      # Add a UUID to the queue, removing oldest if full (O(1) operation)
      # @param uuid [String] The UUID to add
      # @return [void]
      def add(uuid)
        validate_uuid!(uuid)
        
        @mutex.synchronize do
          # Don't add if already exists
          return if @lookup_set.include?(uuid)
          
          # Remove old entry if slot is occupied
          old_uuid = @circular_array[@index]
          if old_uuid
            @lookup_set.delete(old_uuid)
            logger.debug { "[SmartMessage::DDQ::Memory] Evicted UUID: #{old_uuid}" }
          end
          
          # Add new entry
          @circular_array[@index] = uuid
          @lookup_set.add(uuid)
          @index = (@index + 1) % @size
          @count = [@count + 1, @size].min
          
          logger.debug { "[SmartMessage::DDQ::Memory] Added UUID: #{uuid}, count: #{@count}" }
        end
      end
      
      # Get current queue statistics
      # @return [Hash] Statistics about the queue
      def stats
        @mutex.synchronize do
          super.merge(
            current_count: @count,
            utilization: (@count.to_f / @size * 100).round(2),
            next_index: @index
          )
        end
      end
      
      # Clear all entries from the queue
      # @return [void]
      def clear
        @mutex.synchronize do
          @circular_array = Array.new(@size)
          @lookup_set.clear
          @index = 0
          @count = 0
          
          logger.debug { "[SmartMessage::DDQ::Memory] Cleared all entries" }
        end
      end
      
      # Get the storage type identifier
      # @return [Symbol] Storage type
      def storage_type
        :memory
      end
      
      # Get current entries (for debugging/testing)
      # @return [Array<String>] Current UUIDs in insertion order
      def entries
        @mutex.synchronize do
          result = []
          @count.times do |i|
            idx = (@index - @count + i) % @size
            result << @circular_array[idx] if @circular_array[idx]
          end
          result
        end
      end
    end
  end
end