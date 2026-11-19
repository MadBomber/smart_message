# lib/smart_message/transport/stdout_transport.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # Writes each published message to an IO, one serialized message per
    # line.  Useful for development, debugging, and piping messages to
    # another program.
    #
    # Options:
    #   output:   the IO to write to (default: whatever $stdout is when the
    #             message is published)
    #   loopback: also deliver published messages to this transport's own
    #             subscribers (default false)
    #
    # The transport never closes the IO: it did not open it.
    class StdoutTransport < Base
      def default_options
        { output: nil, loopback: false }
      end

      def configure
        @write_mutex = Mutex.new
      end

      # @return [IO] where messages are written
      def output
        @options[:output] || $stdout
      end

      def do_publish(message_class, serialized_message)
        @write_mutex.synchronize do
          output.puts(serialized_message)
          output.flush if output.respond_to?(:flush)
        end

        receive(message_class, serialized_message) if @options[:loopback]
      end
    end
  end
end
