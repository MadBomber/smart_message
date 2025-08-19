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

      # Publish wrapper to STDOUT (two-level serialization)
      def do_publish_wrapper(wrapper)
        # Level 2 serialization: wrapper as JSON for monitoring/routing
        wrapper_json = wrapper.to_json
        
        @output.puts format_wrapper_message(wrapper, wrapper_json)
        @output.flush

        # If loopback is enabled, route the message back through the dispatcher
        if loopback?
          receive(wrapper)
        end
      end

      # Legacy publish method for backward compatibility
      def do_publish(message_header, message_payload)
        @output.puts format_message(message_header, message_payload)
        @output.flush

        # If loopback is enabled, route the message back through the dispatcher  
        if loopback?
          wrapper = SmartMessage::Wrapper::Base.new(header: message_header, payload: message_payload)
          receive(wrapper)
        end
      end

      def connected?
        !@output.closed?
      end

      def disconnect
        @output.close if @output.respond_to?(:close) && @output != $stdout && @output != $stderr
      end

      private

      def format_wrapper_message(wrapper, wrapper_json)
        <<~MESSAGE

          ===================================================
          == SmartMessage Wrapper Published via STDOUT Transport
          == Two-Level Serialization Demo:
          == Level 1 (Payload): #{wrapper._sm_payload} [#{wrapper._sm_header.serializer}]
          == Level 2 (Wrapper): #{wrapper_json} [JSON]
          == Header: #{wrapper._sm_header.inspect}
          == Payload: #{wrapper._sm_payload}
          ===================================================

        MESSAGE
      end

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