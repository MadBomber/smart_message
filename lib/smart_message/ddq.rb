# lib/smart_message/ddq.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'ddq/base'
require_relative 'ddq/memory'
require_relative 'ddq/redis'

module SmartMessage
  # Deduplication Queue (DDQ) for preventing duplicate message processing
  # 
  # Provides a circular queue with O(1) lookup performance for detecting
  # duplicate messages based on UUID. Supports both memory and Redis storage.
  module DDQ
    # Default configuration
    DEFAULT_SIZE = 100
    DEFAULT_STORAGE = :memory
    
    # Create a DDQ instance based on storage type
    def self.create(storage_type, size = DEFAULT_SIZE, options = {})
      case storage_type.to_sym
      when :memory
        Memory.new(size)
      when :redis
        Redis.new(size, options)
      else
        raise ArgumentError, "Unknown DDQ storage type: #{storage_type}. Supported types: :memory, :redis"
      end
    end
  end
end