# lib/smart_message/transport/memory_transport.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # In-memory transport for testing and local development
    # Messages are stored in memory and can be synchronously processed
    class MemoryTransport < Base
      attr_reader :messages

      def default_options
        {
          auto_process: true,
          max_messages: 1000
        }
      end

      # Memory transport doesn't need serialization
      def default_serializer
        nil
      end

      def configure
        @messages = []
        @message_mutex = Mutex.new
      end

      # Implement do_publish for memory transport (no serialization needed)
      def do_publish(message_class, serialized_message)
        # For memory transport, serialized_message is actually the message object
        message = serialized_message
        
        @message_mutex.synchronize do
          # Prevent memory overflow
          @messages.shift if @messages.size >= @options[:max_messages]
          
          # Store the actual message object, no serialization needed
          @messages << {
            message_class: message_class,
            message: message.dup,  # Store a copy to prevent mutation
            published_at: Time.now
          }
        end

        # Auto-process if enabled
        if @options[:auto_process]
          # Route directly without serialization
          @dispatcher.route(message)
        end
      end

      # Override encode_message to return the message object directly
      def encode_message(message)
        # Update header with serializer info (even though we don't serialize)
        message._sm_header.serializer = 'none'
        
        # Return the message object itself (no encoding needed)
        message
      end

      # Get all stored messages
      def all_messages
        @message_mutex.synchronize { @messages.dup }
      end

      # Get message count
      def message_count
        @message_mutex.synchronize { @messages.size }
      end

      # Clear all messages
      def clear_messages
        @message_mutex.synchronize { @messages.clear }
      end

      # Process all pending messages
      def process_all
        messages_to_process = @message_mutex.synchronize { @messages.dup }
        messages_to_process.each do |msg|
          @dispatcher.route(msg[:message])
        end
      end

      def connected?
        true
      end
    end
  end
end