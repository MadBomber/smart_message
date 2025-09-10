# lib/smart_message/transport/stdout_transport.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # STDOUT transport for testing and development
    # This is a publish-only transport that outputs messages to STDOUT
    class StdoutTransport < Base
      def default_options
        {
          output: $stdout,
          format: :pretty  # :pretty or :json
        }
      end

      # Default to JSON for readability in STDOUT
      def default_serializer
        SmartMessage::Serializer::Json.new
      end

      def configure
        @output = @options[:output].is_a?(String) ? File.open(@options[:output], 'w') : @options[:output]
      end


      # Publish message to STDOUT
      def do_publish(message_class, serialized_message)
        logger.debug { "[SmartMessage::StdoutTransport] do_publish called" }
        logger.debug { "[SmartMessage::StdoutTransport] message_class: #{message_class}" }
        
        @output.puts format_message(message_class, serialized_message)
        @output.flush
      rescue => e
        logger.error { "[SmartMessage] Error in stdout transport do_publish: #{e.class.name} - #{e.message}" }
        raise
      end

      def connected?
        !@output.closed?
      end

      def disconnect
        @output.close if @output.respond_to?(:close) && @output != $stdout && @output != $stderr
      end

      # Override subscribe methods to log warnings since this is a publish-only transport
      def subscribe(message_class, process_method, filter_options = {})
        logger.warn { "[SmartMessage::StdoutTransport] Subscription attempt ignored - STDOUT transport is publish-only (message_class: #{message_class}, process_method: #{process_method})" }
      end

      def unsubscribe(message_class, process_method)
        logger.warn { "[SmartMessage::StdoutTransport] Unsubscribe attempt ignored - STDOUT transport is publish-only (message_class: #{message_class}, process_method: #{process_method})" }
      end

      def unsubscribe!(message_class)
        logger.warn { "[SmartMessage::StdoutTransport] Unsubscribe all attempt ignored - STDOUT transport is publish-only (message_class: #{message_class})" }
      end

      private

      def format_message(message_class, serialized_message)
        if @options[:format] == :json
          # Output as JSON for machine parsing
          {
            transport: 'stdout',
            message_class: message_class,
            serialized_message: serialized_message,
            timestamp: Time.now.iso8601
          }.to_json
        else
          # Pretty format for human reading
          <<~MESSAGE

            ===================================================
            == SmartMessage Published via STDOUT Transport
            == Message Class: #{message_class}
            == Serializer: #{@serializer.class.name}
            == Serialized Message:
            #{serialized_message}
            ===================================================

          MESSAGE
        end
      end
    end
  end
end
