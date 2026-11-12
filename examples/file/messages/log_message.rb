# frozen_string_literal: true

# One application log line.
class LogMessage < SmartMessage::Base
  description 'An application log line'
  from 'file-demo'

  LEVELS = %w[DEBUG INFO WARN ERROR FATAL].freeze

  property :level,     required: true, validate: LEVELS, validation_message: "level must be one of #{LEVELS.join(', ')}"
  property :text,      required: true
  property :component, default: 'system'
end
