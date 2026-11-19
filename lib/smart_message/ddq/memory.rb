# lib/smart_message/ddq/memory.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module DDQ
    # Memory-based Deduplication Queue implementation
    #
    # A circular buffer of the last +size+ UUIDs with a Hash index for O(1)
    # lookup.  Every operation runs under one Mutex, so #reserve is an
    # atomic add-if-absent.
    class Memory < Base
      def initialize(size)
        super
        @mutex = Mutex.new
        reset_storage
      end

      # (see Base#reserve)
      def reserve(uuid)
        validate_uuid!(uuid)

        @mutex.synchronize do
          next false if @slots.key?(uuid)

          evicted = @ring[@index]
          @slots.delete(evicted) if evicted

          @ring[@index] = uuid
          @slots[uuid]  = @index
          @index        = (@index + 1) % @size
          true
        end
      end

      # (see Base#release)
      def release(uuid)
        validate_uuid!(uuid)

        @mutex.synchronize do
          slot = @slots.delete(uuid)
          @ring[slot] = nil if slot
        end
        nil
      end

      # Check if a UUID exists in the queue (O(1) operation)
      def contains?(uuid)
        validate_uuid!(uuid)
        @mutex.synchronize { @slots.key?(uuid) }
      end

      # Get current queue statistics
      # @return [Hash] Statistics about the queue
      def stats
        @mutex.synchronize do
          super.merge(
            current_count: @slots.size,
            utilization: (@slots.size.to_f / @size * 100).round(2),
            next_index: @index
          )
        end
      end

      # Clear all entries from the queue
      def clear
        @mutex.synchronize { reset_storage }
        nil
      end

      def storage_type
        :memory
      end

      # Get current entries (for debugging/testing)
      # @return [Array<String>] Current UUIDs, oldest first
      def entries
        @mutex.synchronize { @ring.rotate(@index).compact }
      end

      private

      def reset_storage
        @ring  = Array.new(@size)
        @slots = {}
        @index = 0
      end
    end
  end
end
