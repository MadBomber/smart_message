# lib/smart_message/header.rb
# encoding: utf-8
# frozen_string_literal: true

require 'time'

module SmartMessage
  # Every smart message has a common header format that contains
  # information used to support the dispatching of subscribed
  # messages upon receipt from a transport.
  #
  # Keys this version does not know about are kept in +extensions+ rather
  # than rejected, so an older consumer can receive messages from a newer
  # publisher.
  class Header < Hashie::Dash
    include Hashie::Extensions::Coercion
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
      description: "Optional unique identifier of the intended recipient entity. When nil, message is broadcast to all subscribers"

    property :reply_to,
      description: "Optional unique identifier of the entity that should receive replies to this message. Defaults to 'from' entity if not specified"

    # Serialization tracking for message architecture
    property :serializer,
      description: "Class name of the serializer used to encode the message (e.g., 'SmartMessage::Serializer::Json')"

    property :extensions,
      default: {},
      description: "Header fields this version of SmartMessage does not define, kept so they survive a round trip"

    # A timestamp that crossed a serializer arrives as a String
    coerce_key :published_at, ->(value) { value.is_a?(String) ? Time.parse(value) : value }

    # @param attributes [Hash] header fields with String or Symbol keys;
    #   unknown fields are collected into +extensions+
    def initialize(attributes = {}, &block)
      super(self.class.partition_attributes(attributes), &block)
    end

    # Split a raw hash into declared fields plus an :extensions entry.
    def self.partition_attributes(attributes)
      known   = {}
      unknown = {}

      (attributes || {}).each do |key, value|
        name = key.to_sym
        property?(name) ? known[name] = value : unknown[name] = value
      end

      return known if unknown.empty?

      extensions = (known[:extensions] || {}).to_h.transform_keys(&:to_sym)
      known.merge(extensions: extensions.merge(unknown))
    end

    def [](property)
      super(property.to_sym)
    end

    # Coercion wraps []= when it is included, so an override has to call
    # the coercing writer itself or coerce_key would be skipped.
    def []=(property, value)
      set_value_with_coercion(property.to_sym, value)
    end

    # @return [Hash] every header field, Symbol keys
    def to_h
      self.class.properties.to_h { [it, self[it]] }
    end
    alias to_hash to_h

    # @return [Hash] the fields worth sending: no nils, no empty extensions
    def to_wire
      to_h.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    private

    def initialize_copy(other)
      super
      self[:extensions] = other[:extensions].dup
    end
  end
end
