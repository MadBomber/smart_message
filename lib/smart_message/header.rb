# lib/smart_message/header.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative './property_descriptions'
require_relative './property_validations'

module SmartMessage
  # Every smart message has a common header format that contains
  # information used to support the dispatching of subscribed
  # messages upon receipt from a transport.
  class Header < Hashie::Dash
    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::MethodAccess
    include SmartMessage::PropertyDescriptions
    include SmartMessage::PropertyValidations

    # Common attributes of the smart message standard header
    property :uuid, 
      required: true,
      message: "UUID is required for message tracking and deduplication",
      description: "Unique identifier for this specific message instance, used for tracking and deduplication"
    
    property :message_class, 
      required: true,
      message: "Message class is required to identify the message type",
      description: "Fully qualified class name of the message type (e.g. 'OrderMessage', 'PaymentNotification')"
    
    property :published_at, 
      required: true,
      message: "Published timestamp is required for message ordering",
      description: "Timestamp when the message was published by the sender, used for ordering and debugging"
    
    property :publisher_pid, 
      required: true,
      message: "Publisher process ID is required for debugging and traceability",
      description: "Process ID of the publishing application, useful for debugging and tracing message origins"
    
    property :version, 
      required: true, 
      default: 1,
      message: "Message version is required for schema compatibility",
      description: "Schema version of the message format, used for schema evolution and compatibility checking",
      validate: ->(v) { v.is_a?(Integer) && v > 0 },
      validation_message: "Header version must be a positive integer"
    
    # Message addressing properties for entity-to-entity communication
    property :from,
      required: true,
      message: "From entity ID is required for message routing and replies",
      description: "Unique identifier of the entity sending this message, used for routing responses and audit trails"
    
    property :to,
      required: false,
      description: "Optional unique identifier of the intended recipient entity. When nil, message is broadcast to all subscribers"
    
    property :reply_to,
      required: false,
      description: "Optional unique identifier of the entity that should receive replies to this message. Defaults to 'from' entity if not specified"
    
    # Serialization tracking for message architecture
    property :serializer,
      required: false,
      description: "Class name of the serializer used to encode the payload (e.g., 'SmartMessage::Serializer::Json'). Used by DLQ and cross-serializer gateway patterns"
  end
end