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

      # Publish message to STDOUT
      def do_publish(message_header, message_payload)
        @output.puts format_message(message_header, message_payload)
        @output.flush

        # If loopback is enabled, route the message back through the dispatcher
        receive(message_header, message_payload) if loopback?
      end

      def connected?
        !@output.closed?
      end

      def disconnect
        @output.close if @output.respond_to?(:close) && @output != $stdout && @output != $stderr
      end

      private

      def format_message(message_header, message_payload)
        <<~MESSAGE

          ===================================================
          == SmartMessage Published via STDOUT Transport
          == Header: #{message_header.inspect}
          == Payload: #{message_payload}
          ===================================================

        MESSAGE
      end
    end
  end
end