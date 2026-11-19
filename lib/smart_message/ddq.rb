# lib/smart_message/ddq.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Deduplication Queue (DDQ) for preventing duplicate message processing
  #
  # Remembers message UUIDs so a handler does not process the same message
  # twice.  Supports memory storage (per process) and Redis storage (shared
  # between processes).
  module DDQ
    # Default configuration
    DEFAULT_SIZE    = 100
    DEFAULT_STORAGE = :memory

    # Create a DDQ instance based on storage type
    #
    # @param storage_type [Symbol] :memory or :redis
    # @param size [Integer] how many UUIDs to remember (memory storage)
    # @param options [Hash] backend options (see DDQ::Redis)
    # @raise [ArgumentError] for an unknown storage type
    def self.create(storage_type, size = DEFAULT_SIZE, options = {})
      case storage_type&.to_sym
      when :memory then Memory.new(size)
      when :redis  then Redis.new(size, options)
      else
        raise ArgumentError, "Unknown DDQ storage type: #{storage_type.inspect}. Supported types: :memory, :redis"
      end
    end
  end
end
