# lib/smart_message/deduplication.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Deduplication configuration for message classes.
  #
  #   class OrderMessage < SmartMessage::Base
  #     ddq_size 500            # optional, default DDQ::DEFAULT_SIZE
  #     ddq_storage :memory     # optional, default DDQ::DEFAULT_STORAGE
  #     enable_deduplication!
  #   end
  #
  # The settings are inherited by subclasses.  The queues themselves belong
  # to the dispatcher: there is one Deduplication Queue (DDQ) per handler
  # per message class, created when the handler subscribes.  A message's
  # UUID is reserved before its handler runs and released if the handler
  # fails, so a redelivery that arrives while the first copy is still being
  # processed is skipped.
  module Deduplication
    STORAGE_TYPES = %i[memory redis].freeze

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Configure DDQ size for this message class
      # @param size [Integer] Maximum number of UUIDs to track
      def ddq_size(size)
        unless size.is_a?(Integer) && size.positive?
          raise ArgumentError, "DDQ size must be a positive integer, got: #{size.inspect}"
        end

        set_setting(:ddq_size, size)
      end

      # Configure DDQ storage type for this message class
      # @param storage [Symbol] Storage type (:memory or :redis)
      # @param options [Hash] Additional options for the storage backend
      def ddq_storage(storage, **options)
        unless storage.respond_to?(:to_sym) && STORAGE_TYPES.include?(storage.to_sym)
          raise ArgumentError, "DDQ storage must be :memory or :redis, got: #{storage.inspect}"
        end

        set_setting(:ddq_storage, storage.to_sym)
        set_setting(:ddq_options, options)
      end

      # Enable deduplication for this message class
      def enable_deduplication!
        set_setting(:ddq_enabled, true)
      end

      # Disable deduplication for this message class
      def disable_deduplication!
        set_setting(:ddq_enabled, false)
      end

      # Check if deduplication is enabled
      # @return [Boolean] true if DDQ is enabled
      def ddq_enabled?
        setting(:ddq_enabled, false)
      end

      # Get the current DDQ configuration
      # @return [Hash] Current DDQ configuration, with defaults filled in
      def ddq_config
        {
          enabled: ddq_enabled?,
          size:    setting(:ddq_size, DDQ::DEFAULT_SIZE),
          storage: setting(:ddq_storage, DDQ::DEFAULT_STORAGE),
          options: setting(:ddq_options, {})
        }
      end

      # Statistics for this class's deduplication queues, one entry per
      # handler on each configured transport.
      # @return [Hash] { enabled:, queues: { "Class:handler" => stats } }
      def ddq_stats
        return { enabled: false } unless ddq_enabled?

        queues = each_dispatcher.reduce({}) { |stats, dispatcher| stats.merge(dispatcher.ddq_stats(whoami)) }
        { enabled: true, queues: queues }
      end

      # Forget every UUID this class's handlers have seen.
      def clear_ddq!
        each_dispatcher.each { |dispatcher| dispatcher.clear_ddqs(whoami) }
        nil
      end

      private

      # The dispatchers of this class's transports
      def each_dispatcher
        transports.filter_map { |transport_instance| transport_instance.dispatcher if transport_instance.respond_to?(:dispatcher) }.uniq
      end
    end

    # Get the message UUID
    # @return [String, nil] The message UUID
    def uuid
      _sm_header&.uuid
    end
  end
end
