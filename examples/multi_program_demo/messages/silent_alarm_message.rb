#!/usr/bin/env ruby
# messages/silent_alarm_message.rb
# Silent alarm message sent by banks to the Police Department during security incidents
# Triggers immediate police response with unit dispatch based on severity level

require_relative '../../../lib/smart_message'

module Messages
  class SilentAlarmMessage < SmartMessage::Base
    version 1

    description <<~DESC
      An automatic emergency security alert message sent by banking institutions, stores or houses
      with monitored secutity systems. This message is used to the Police Department when security breaches,
      robberies, or suspicious activities are detected, triggering immediate law enforcement response with
      automatic unit dispatch based on the threat severity level.
    DESC

    transport  SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::Json.new

    VALID_ALARM_TYPES = %w[robbery vault_breach suspicious_activity]

    property :bank_name, required: true, description: "Official name of the bank triggering the alarm (e.g., 'First National Bank')"
    property :location, required: true, description: "Physical address of the bank location where alarm was triggered"
    property :alarm_type, required: true,
      validate: ->(v) { VALID_ALARM_TYPES.include?(v) },
      validation_message: "Alarm type must be: #{VALID_ALARM_TYPES.join(', ')}",
      description: "Type of security incident detected (VALID_ALARM_TYPES.join(', '))"
    property :timestamp, required: true, description: "Exact time when the alarm was triggered (YYYY-MM-DD HH:MM:SS format)"
    property :severity, required: true,
      validate: ->(v) { %w[low medium high critical].include?(v) },
      validation_message: "Severity must be low, medium, high, or critical",
      description: "Urgency level of the security threat (low/medium/high/critical)"
    property :details, description: "Additional descriptive information about the security incident and current situation"
  end
end
