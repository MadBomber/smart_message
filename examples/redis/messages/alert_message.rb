# examples/redis/messages/alert_message.rb
# frozen_string_literal: true

require_relative '../../../lib/smart_message'

# A notification that needs somebody's attention.
class AlertMessage < SmartMessage::Base
  description 'An alert raised by a smart home device'

  SEVERITIES = %w[low medium high critical].freeze

  property :alert_type,      required: true, description: 'high_temperature, motion_detected, battery_low, ...'
  property :severity,        required: true, validate: SEVERITIES,
                             validation_message: "Severity must be one of: #{SEVERITIES.join(', ')}",
                             description: "How urgent the alert is: #{SEVERITIES.join(', ')}"
  property :device_id,       required: true, description: 'The device that raised the alert'
  property :location,        description: 'Where the device is installed'
  property :message,         required: true, description: 'Human-readable description of the condition'
  property :requires_action, default: false, description: 'True when a person has to do something'
  property :timestamp,       default: -> { Time.now.iso8601 }, description: 'When the alert was raised (ISO 8601)'
end
