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

      def configure
        @messages = []
        @message_mutex = Mutex.new
      end

      # Publish message to memory queue
      def do_publish(message_header, message_payload)
        @message_mutex.synchronize do
          # Prevent memory overflow
          @messages.shift if @messages.size >= @options[:max_messages]
          
          @messages << {
            header: message_header,
            payload: message_payload,
            published_at: Time.now
          }
        end

        # Auto-process if enabled
        if @options[:auto_process]
          wrapper = SmartMessage::Wrapper::Base.new(header: message_header, payload: message_payload)
          receive(wrapper)
        end
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
          receive(msg[:header], msg[:payload])
        end
      end

      def connected?
        true
      end
    end
  end
end