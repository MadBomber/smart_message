# lib/smart_message/ddq/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module DDQ
    # Base class for Deduplication Queue implementations
    #
    # Defines the interface that all DDQ storage backends must implement.
    # The dispatcher uses #reserve before a handler runs and #release when
    # the handler fails; both must be atomic.
    class Base
      attr_reader :size

      def initialize(size)
        @size = size
        validate_size!
      end

      # Atomically record a UUID unless it is already recorded.
      # @param uuid [String] The UUID to reserve
      # @return [Boolean] true when this call recorded it, false when it was
      #   already there (a duplicate)
      def reserve(uuid)
        raise NotImplementedError, "Subclasses must implement #reserve"
      end

      # Forget a UUID, so the message can be processed again.
      # @param uuid [String] The UUID to release
      # @return [void]
      def release(uuid)
        raise NotImplementedError, "Subclasses must implement #release"
      end

      # Check if a UUID exists in the queue
      # @param uuid [String] The UUID to check
      # @return [Boolean] true if UUID exists, false otherwise
      def contains?(uuid)
        raise NotImplementedError, "Subclasses must implement #contains?"
      end

      # Add a UUID to the queue.  Same as #reserve without the answer.
      # @param uuid [String] The UUID to add
      # @return [void]
      def add(uuid)
        reserve(uuid)
        nil
      end

      # Get current queue statistics
      # @return [Hash] Statistics about the queue
      def stats
        {
          size: @size,
          storage_type: storage_type,
          implementation: self.class.name
        }
      end

      # Clear all entries from the queue
      # @return [void]
      def clear
        raise NotImplementedError, "Subclasses must implement #clear"
      end

      # Get the storage type identifier
      # @return [Symbol] Storage type (:memory, :redis, etc.)
      def storage_type
        raise NotImplementedError, "Subclasses must implement #storage_type"
      end

      private

      def logger
        SmartMessage::Logger.default
      end

      def validate_size!
        return if @size.is_a?(Integer) && @size.positive?

        raise ArgumentError, "DDQ size must be a positive integer, got: #{@size.inspect}"
      end

      def validate_uuid!(uuid)
        return if uuid.is_a?(String) && !uuid.empty?

        raise ArgumentError, "UUID must be a non-empty string, got: #{uuid.inspect}"
      end
    end
  end
end
