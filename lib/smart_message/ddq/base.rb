# lib/smart_message/ddq/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module DDQ
    # Base class for Deduplication Queue implementations
    # 
    # Defines the interface that all DDQ storage backends must implement.
    # Provides circular queue semantics with O(1) lookup performance.
    class Base
      attr_reader :size, :logger
      
      def initialize(size)
        @size = size
        @logger = SmartMessage::Logger.default
        validate_size!
      end
      
      # Check if a UUID exists in the queue
      # @param uuid [String] The UUID to check
      # @return [Boolean] true if UUID exists, false otherwise
      def contains?(uuid)
        raise NotImplementedError, "Subclasses must implement #contains?"
      end
      
      # Add a UUID to the queue (removes oldest if full)
      # @param uuid [String] The UUID to add
      # @return [void]
      def add(uuid)
        raise NotImplementedError, "Subclasses must implement #add"
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
      
      def validate_size!
        unless @size.is_a?(Integer) && @size > 0
          raise ArgumentError, "DDQ size must be a positive integer, got: #{@size.inspect}"
        end
      end
      
      def validate_uuid!(uuid)
        unless uuid.is_a?(String) && !uuid.empty?
          raise ArgumentError, "UUID must be a non-empty string, got: #{uuid.inspect}"
        end
      end
    end
  end
end