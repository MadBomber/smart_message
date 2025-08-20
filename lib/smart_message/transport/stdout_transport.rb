# lib/smart_message/transport/stdout_transport.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # STDOUT transport for testing and development
    # This transport outputs messages to STDOUT and optionally loops them back
    class StdoutTransport < Base
      def default_options
        {
          loopback: false,
          output: $stdout
        }
      end

      def configure
        @output = @options[:output].is_a?(String) ? File.open(@options[:output], 'w') : @options[:output]
      end

      # Enable/disable loopback mode
      def loopback=(enabled)
        @options[:loopback] = enabled
      end

      def loopback?
        @options[:loopback]
      end

      # Publish message to STDOUT (single-tier serialization)
      def do_publish(message_class, serialized_message)
        logger.debug { "[SmartMessage::StdoutTransport] do_publish called" }
        logger.debug { "[SmartMessage::StdoutTransport] message_class: #{message_class}" }
        
        @output.puts format_message(message_class, serialized_message)
        @output.flush

        # If loopback is enabled, route the message back through the dispatcher
        if loopback?
          logger.debug { "[SmartMessage::StdoutTransport] Loopback enabled, calling receive" }
          receive(message_class, serialized_message)
        end
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

      private

      def format_message(message_class, serialized_message)
        <<~MESSAGE

          ===================================================
          == SmartMessage Published via STDOUT Transport
          == Single-Tier Serialization:
          == Message Class: #{message_class}
          == Serialized Message: #{serialized_message}
          ===================================================

        MESSAGE
      end
    end
  end
end
