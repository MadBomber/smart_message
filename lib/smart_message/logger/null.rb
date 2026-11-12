# lib/smart_message/logger/null.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Logger
    # Null logger implementation that discards all log messages
    #
    # This is what SmartMessage uses when no logger is configured.  Message
    # blocks are never evaluated.
    #
    # Usage:
    #   # Disable all SmartMessage logging (also the default)
    #   SmartMessage.configure do |config|
    #     config.logger = nil
    #   end
    class Null < Base
      # Above FATAL, so every level predicate answers false
      SILENT = LEVELS.size

      def level
        SILENT
      end

      # Level changes are accepted and ignored
      def level=(value)
        SmartMessage::Logger.severity(value)
        value
      end

      private

      def log(_severity, _message, _data)
        nil
      end
    end
  end
end
