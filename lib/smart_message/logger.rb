# lib/smart_message/logger.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'logger/base'
require_relative 'logger/default'
require_relative 'logger/lumberjack'

module SmartMessage
  module Logger
    class << self
      # Global default logger instance
      def default(options = {})
        @default ||= Lumberjack.new(**options)
      end

      # Set the default logger
      def default=(logger)
        @default = logger
      end
    end
  end
end
