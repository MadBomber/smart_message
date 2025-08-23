#!/usr/bin/env ruby
# examples/messages/fire_emergency_message.rb
#
# Fire emergency message sent by houses to the Fire Department when fires are detected
# Triggers immediate fire department response with engine dispatch based on fire severity and type
#
require_relative '../../../lib/smart_message'

module Messages
  class FireEmergencyMessage < SmartMessage::Base
    version 1

    description "Critical fire emergency alert message sent by residential monitoring systems to the Fire Department when smoke, heat, or fire is detected, triggering immediate emergency response with fire engine dispatch, specialized equipment deployment, and rescue operations based on fire type, severity, and occupant safety status"

    transport SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::Json.new

    VALID_FIRE_TYPES = %w[fire kitchen electrical basement garage wildfire]

    property :house_address, required: true,
      description: "Full street address of the house where fire was detected"

    property :fire_type, required: true,
      validate: ->(v) { VALID_FIRE_TYPES.include?(v) },
      validation_message: "Fire type must be: #{VALID_FIRE_TYPES.join(', ')}",
      description: "Classification of fire origin and type (kitchen/electrical/basement/garage/wildfire)"

    property :severity, required: true,
      validate: ->(v) { %w[small medium large out_of_control].include?(v) },
      validation_message: "Severity must be small, medium, large, or out_of_control",
      description: "Current intensity and spread level of the fire (small/medium/large/out_of_control)"

    property :timestamp, required: true,
      description: "Exact time when the fire was first detected (YYYY-MM-DD HH:MM:SS format)"

    property :occupants_status,
      description: "Current safety status of people in the house (safe/evacuated/trapped/rescued)"

    property :spread_risk,
      description: "Assessment of fire's potential to spread to neighboring structures"
  end
end
