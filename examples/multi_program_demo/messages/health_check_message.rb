require 'smart_message'
require 'smart_message/transport/redis_transport'
require 'smart_message/serializer/json'

module Messages
  # Health check message broadcast by the Health Department to monitor city services
  # Sent every 5 seconds to all services to verify operational status
  class HealthCheckMessage < SmartMessage::Base
    version 1
    
    description "Health monitoring message broadcast by the Health Department every 5 seconds to verify operational status of all city services including police, fire, banks, and residential monitoring systems"
    
    transport SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::Json.new

    property :timestamp, required: true, description: "When the health check was initiated (YYYY-MM-DD HH:MM:SS format)"
    property :check_id, required: true, description: "Unique identifier for this health check request (UUID format)"
  end
end
