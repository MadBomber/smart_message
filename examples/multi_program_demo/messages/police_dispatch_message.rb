require 'smart_message'
require 'smart_message/transport/redis_transport'
require 'smart_message/serializer/json'

module Messages
  # Police dispatch message sent by the Police Department in response to emergency calls
  # Contains unit assignments and response details for security incidents and crimes
  class PoliceDispatchMessage < SmartMessage::Base
    version 1
    
    description "Law enforcement dispatch coordination message sent by the Police Department in response to emergency calls and security incidents, containing unit assignments, response priorities, and tactical deployment information for crimes, alarms, and public safety threats"
    
    transport SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::Json.new

    property :dispatch_id, required: true, description: "Unique hexadecimal identifier for this police dispatch operation"
    property :units_assigned, required: true, description: "Array of police unit call signs assigned to respond (e.g., ['Unit-101', 'Unit-102'])"
    property :location, required: true, description: "Street address or location where police units should respond"
    property :incident_type, required: true, description: "Classification of the incident requiring police response (e.g., 'robbery', 'suspicious_activity')"
    property :priority, required: true,
      validate: ->(v) { %w[low medium high emergency].include?(v) },
      validation_message: "Priority must be low, medium, high, or emergency",
      description: "Response urgency level determining dispatch speed (low/medium/high/emergency)"
    property :estimated_arrival, description: "Projected time for first unit arrival at the scene (e.g., '5 minutes')"
    property :timestamp, required: true, description: "Exact time when the dispatch was initiated (YYYY-MM-DD HH:MM:SS format)"
  end
end