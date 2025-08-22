require 'smart_message'
require 'smart_message/transport/redis_transport'
require 'smart_message/serializer/json'

module Messages
  # Health status response message sent by city services back to the Health Department
  # Contains operational status with color-coded display (green=healthy, yellow=warning, orange=critical, red=failed)
  class HealthStatusMessage < SmartMessage::Base
    version 1
    
    description "Operational status response message sent by city services to the Health Department in response to health check requests, providing real-time service condition reporting with color-coded status levels for monitoring dashboard display"
    
    transport SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::Json.new

    property :service_name, required: true, description: "Name of the city service reporting its status (e.g., 'police-department', 'fire-department')"
    property :status, required: true,
      validate: ->(v) { %w[healthy warning critical failed].include?(v) },
      validation_message: "Status must be healthy, warning, critical, or failed",
      description: "Current operational status of the service (healthy/warning/critical/failed)"
    property :timestamp, required: true, description: "When the status was generated (YYYY-MM-DD HH:MM:SS format)"
    property :check_id, required: true, description: "ID of the health check request this message responds to"
    property :details, description: "Additional status information describing current service conditions"
    property :uptime_seconds, description: "Number of seconds the service has been running since startup"
  end
end