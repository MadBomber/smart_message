# lib/smart_message/logger.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage::Logger
  # Logger module provides logging capabilities for SmartMessage
  # The Default logger automatically uses Rails.logger if available,
  # otherwise falls back to a standard Ruby Logger
end # module SmartMessage::Logger

# Load the base class first
require_relative 'logger/base'

# Load the default logger implementation
require_relative 'logger/default'
