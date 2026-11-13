# lib/smart_message/transport/memory_transport.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # In-memory transport for testing and local development.
    #
    # Options:
    #   auto_process:   deliver to subscribers on publish (default true)
    #   store_messages: keep published messages for #all_messages and
    #                   #process_all (default: true only when auto_process
    #                   is false)
    #   max_messages:   how many stored messages to keep (default 1000)
    #   serialize:      encode on publish and decode on delivery, as a real
    #                   transport does (default true).  With false, handlers
    #                   receive copies of the published object and type
    #                   changes caused by serialization go unnoticed.
    class MemoryTransport < Base
      def default_options
        {
          auto_process:   true,
          store_messages: nil,
          max_messages:   1000,
          serialize:      true
        }
      end

      def configure
        max = @options[:max_messages]
        unless max.is_a?(Integer) && max.positive?
          raise ArgumentError, "max_messages must be a positive Integer, got: #{max.inspect}"
        end

        @messages      = []
        @message_mutex = Mutex.new
      end

      # @return [Boolean] are published messages kept?
      def store_messages?
        @options[:store_messages].nil? ? !@options[:auto_process] : @options[:store_messages]
      end

      def encode_message(message)
        return super if @options[:serialize]

        message._sm_header.serializer = 'none'
        message.dup
      end

      # @param payload [String, SmartMessage::Base] the encoded message, or
      #   a copy of the message when serialize: false
      def do_publish(message_class, payload)
        store(message_class, payload) if store_messages?
        deliver(message_class, payload) if @options[:auto_process]
      end

      # @return [Array<Hash>] stored entries: { message_class:, payload:, published_at: }
      def all_messages
        @message_mutex.synchronize { @messages.dup }
      end
      alias messages all_messages

      # Get message count
      def message_count
        @message_mutex.synchronize { @messages.size }
      end

      # Clear all messages
      def clear_messages
        @message_mutex.synchronize { @messages.clear }
      end

      # Deliver every stored message to subscribers and remove it from the
      # store, so calling this twice does not deliver anything twice.
      # @return [Integer] how many messages were processed
      def process_all
        pending = @message_mutex.synchronize do
          drained = @messages.dup
          @messages.clear
          drained
        end

        pending.each { |entry| deliver(entry[:message_class], entry[:payload]) }
        pending.size
      end

      private

      def store(message_class, payload)
        @message_mutex.synchronize do
          @messages.shift while @messages.size >= @options[:max_messages]
          @messages << { message_class: message_class, payload: payload, published_at: Time.now }
        end
      end

      def deliver(message_class, payload)
        if payload.is_a?(SmartMessage::Base)
          @dispatcher.route(payload)
        else
          receive(message_class, payload)
        end
      end
    end
  end
end
