# lib/smart_message/logger/null.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Logger
    # Null logger implementation that discards all log messages
    #
    # This logger provides a no-op implementation of the standard logging
    # interface. All log messages are silently discarded, making it useful
    # for applications that want to completely disable SmartMessage logging.
    #
    # Usage:
    #   # Disable all SmartMessage logging
    #   SmartMessage.configure do |config|
    #     config.logger = SmartMessage::Logger::Null.new
    #   end
    #
    #   # Or set logger to nil (framework will use Null logger automatically)
    #   SmartMessage.configure do |config|
    #     config.logger = nil
    #   end
    class Null < Base
      def initialize
        # No setup needed for null logger
      end

      # All logging methods are no-ops that accept any arguments
      # and return nil immediately without processing

      def debug(*args, &block)
        # Silently discard
        nil
      end

      def info(*args, &block)
        # Silently discard
        nil
      end

      def warn(*args, &block)
        # Silently discard
        nil
      end

      def error(*args, &block)
        # Silently discard
        nil
      end

      def fatal(*args, &block)
        # Silently discard
        nil
      end

      # Additional methods that might be called on loggers

      def level
        ::Logger::FATAL + 1  # Higher than FATAL to ensure nothing logs
      end

      def level=(value)
        # Ignore level changes
      end

      def close
        # Nothing to close
      end

      def respond_to_missing?(method_name, include_private = false)
        # Pretend to respond to any logging method
        true
      end

      def method_missing(method_name, *args, &block)
        # Silently handle any other logging calls
        nil
      end
    end
  end
end