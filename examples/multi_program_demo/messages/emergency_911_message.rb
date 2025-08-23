#!/usr/bin/env ruby
# examples/messages/emergency_911_message.rb

require_relative '../../../lib/smart_message'

module Messages
  class Emergency911Message < SmartMessage::Base
    version 1

    description 'Emergency 911 call for reporting fires, crimes, accidents, medical emergencies, or other urgent situations requiring police, fire, or medical response'

    transport  SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::Json.new

    # Caller information
    property :caller_name,
             description: 'Name of the person calling 911'

    property :caller_phone,
             description: 'Phone number of the caller'

    property :caller_location,
             required: true,
             description: 'Location of the emergency (address or description)'

    property :emergency_type,
             required: true,
             validate: ->(v) { %w[fire medical crime accident hazmat rescue other].include?(v) },
             validation_message: 'Emergency type must be one of: fire, medical, crime, accident, hazmat, rescue, other',
             description: 'Type of emergency being reported'

    property :description,
             required: true,
             description: 'Detailed description of the emergency'

    property :severity,
             validate: ->(v) { %w[critical high medium low].include?(v) },
             validation_message: 'Severity must be one of: critical, high, medium, low',
             description: 'Perceived severity of the emergency'

    property :injuries_reported,
             description: 'Are there injuries? (true/false)'

    property :number_of_victims,
             description: 'Number of people affected or injured'

    property :fire_involved,
             description: 'Is there fire involved? (true/false)'

    property :weapons_involved,
             description: 'Are weapons involved? (true/false)'

    property :hazardous_materials,
             description: 'Are hazardous materials involved? (true/false)'

    property :vehicles_involved,
             description: 'Number of vehicles involved (for accidents)'

    property :suspects_on_scene,
             description: 'Are suspects still on scene? (true/false)'

    property :additional_info,
             description: 'Any additional information provided by caller'

    property :dispatch_to,
             description: 'Which departments to dispatch to (array of department names)'

    property :priority,
             description: 'Dispatch priority level (1-5, 1 being highest)'

    property :call_id,
             description: 'Unique identifier for this 911 call'

    property :call_received_at,
             default: -> { Time.now.iso8601 },
             description: 'When the 911 call was received'
  end
end
