# lib/smart_message/deduplication.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'ddq'

module SmartMessage
  # Deduplication functionality for message classes
  # 
  # Provides class-level configuration and instance-level deduplication
  # checking using a Deduplication Queue (DDQ).
  module Deduplication
    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@ddq_size, DDQ::DEFAULT_SIZE)
      base.instance_variable_set(:@ddq_storage, DDQ::DEFAULT_STORAGE)
      base.instance_variable_set(:@ddq_options, {})
      base.instance_variable_set(:@ddq_enabled, false)
      base.instance_variable_set(:@ddq_instance, nil)
    end
    
    module ClassMethods
      # Configure DDQ size for this message class
      # @param size [Integer] Maximum number of UUIDs to track
      def ddq_size(size)
        unless size.is_a?(Integer) && size > 0
          raise ArgumentError, "DDQ size must be a positive integer, got: #{size.inspect}"
        end
        @ddq_size = size
        reset_ddq_instance! if ddq_enabled?
      end
      
      # Configure DDQ storage type for this message class
      # @param storage [Symbol] Storage type (:memory or :redis)
      # @param options [Hash] Additional options for the storage backend
      def ddq_storage(storage, **options)
        unless [:memory, :redis].include?(storage.to_sym)
          raise ArgumentError, "DDQ storage must be :memory or :redis, got: #{storage.inspect}"
        end
        @ddq_storage = storage.to_sym
        @ddq_options = options
        reset_ddq_instance! if ddq_enabled?
      end
      
      # Enable deduplication for this message class
      def enable_deduplication!
        @ddq_enabled = true
        get_ddq_instance # Initialize the DDQ
      end
      
      # Disable deduplication for this message class
      def disable_deduplication!
        @ddq_enabled = false
        @ddq_instance = nil
      end
      
      # Check if deduplication is enabled
      # @return [Boolean] true if DDQ is enabled
      def ddq_enabled?
        !!@ddq_enabled
      end
      
      # Get the current DDQ configuration
      # @return [Hash] Current DDQ configuration
      def ddq_config
        {
          enabled: ddq_enabled?,
          size: @ddq_size,
          storage: @ddq_storage,
          options: @ddq_options
        }
      end
      
      # Get DDQ statistics
      # @return [Hash] DDQ statistics
      def ddq_stats
        return { enabled: false } unless ddq_enabled?
        
        ddq = get_ddq_instance
        if ddq
          ddq.stats.merge(enabled: true)
        else
          { enabled: true, error: "DDQ instance not available" }
        end
      end
      
      # Clear the DDQ
      def clear_ddq!
        return unless ddq_enabled?
        
        ddq = get_ddq_instance
        ddq&.clear
      end
      
      # Check if a UUID is a duplicate (for external use)
      # @param uuid [String] The UUID to check
      # @return [Boolean] true if UUID is a duplicate
      def duplicate_uuid?(uuid)
        return false unless ddq_enabled?
        
        ddq = get_ddq_instance
        ddq ? ddq.contains?(uuid) : false
      end
      
      # Get the DDQ instance (exposed for testing)
      def get_ddq_instance
        return nil unless ddq_enabled?
        
        # Return cached instance if available and configuration hasn't changed
        if @ddq_instance
          return @ddq_instance
        end
        
        # Create new DDQ instance
        size = @ddq_size
        storage = @ddq_storage
        options = @ddq_options
        
        ddq = DDQ.create(storage, size, options)
        @ddq_instance = ddq
        
        SmartMessage::Logger.default.debug do
          "[SmartMessage::Deduplication] Created DDQ for #{self.name}: " \
          "storage=#{storage}, size=#{size}, options=#{options}"
        end
        
        ddq
      rescue => e
        SmartMessage::Logger.default.error do
          "[SmartMessage::Deduplication] Failed to create DDQ for #{self.name}: #{e.message}"
        end
        nil
      end
      
      private
      
      def reset_ddq_instance!
        @ddq_instance = nil
      end
    end
    
    # Instance methods for deduplication checking
    
    # Check if this message is a duplicate based on its UUID
    # @return [Boolean] true if this message UUID has been seen before
    def duplicate?
      return false unless self.class.ddq_enabled?
      return false unless uuid
      
      self.class.duplicate_uuid?(uuid)
    end
    
    # Mark this message as processed (add UUID to DDQ)
    # @return [void]
    def mark_as_processed!
      return unless self.class.ddq_enabled?
      return unless uuid
      
      ddq = self.class.send(:get_ddq_instance)
      if ddq
        ddq.add(uuid)
        SmartMessage::Logger.default.debug do
          "[SmartMessage::Deduplication] Marked UUID as processed: #{uuid}"
        end
      end
    end
    
    # Get the message UUID
    # @return [String, nil] The message UUID
    def uuid
      _sm_header&.uuid
    end
  end
end