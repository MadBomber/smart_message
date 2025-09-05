# lib/smart_message/logger.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'logger/base'
require_relative 'logger/default'
require_relative 'logger/lumberjack'

module SmartMessage
  module Logger
    class << self
      # Global default logger instance - uses configuration if available
      def default(options = {})
        # Always check current configuration first (don't cache when config is available)
        if defined?(SmartMessage.configuration) && SmartMessage.configuration.logger_configured?
          SmartMessage.configuration.default_logger
        else
          # Cache the framework default logger only when no configuration
          @default ||= Lumberjack.new(**options)
        end
      end

      # Set the default logger
      def default=(logger)
        @default = logger
      end
      
      # Reset the cached default logger
      def reset!
        @default = nil
      end
    end
  end
end
