# lib/smart_message/envelope.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # The envelope codec: the one place where a message becomes bytes and
  # bytes become a message.  Transports only move the bytes.
  #
  # On the wire a message is one flat structure: its properties plus a
  # '_sm_header' entry.
  module Envelope
    HEADER_KEY = :_sm_header

    module_function

    # Serialize a message.
    #
    # @param message [SmartMessage::Base]
    # @param serializer [SmartMessage::Serializer::Base]
    # @return [String] the payload to hand to a transport
    # @raise [SmartMessage::Errors::SerializationError]
    def encode(message, serializer)
      message._sm_header.serializer = serializer.class.name
      serializer.encode(message.to_h.merge(HEADER_KEY => message._sm_header.to_wire))
    end

    # Rebuild a message from a payload.
    #
    # Input is not trusted.  The class named in the header must be a loaded
    # SmartMessage::Base descendant, it must match the channel the payload
    # arrived on (when there is one), and only declared properties are
    # passed to the message.
    #
    # @param payload [String] the serialized message
    # @param serializer [SmartMessage::Serializer::Base]
    # @param channel [String, nil] the message class the transport received
    #   this payload for; nil when the transport has no channels
    # @param fallback_header [Hash, nil] header to use when the payload
    #   carries none (dead letter queue entries store it separately)
    # @return [SmartMessage::Base]
    # @raise [SmartMessage::Errors::DecodeError] not an envelope, or the
    #   message could not be built from it (a bad published_at, a coerce_key
    #   that raised, ...); the original error is the cause
    # @raise [SmartMessage::Errors::UnknownMessageClass]
    # @raise [SmartMessage::Errors::MessageClassMismatch]
    def decode(payload, serializer:, channel: nil, fallback_header: nil)
      data   = symbolize(serializer.decode(payload))
      header = extract_header(data, fallback_header)

      class_name = header[:message_class].to_s
      assert_channel_matches!(class_name, channel)

      message_class = resolve_message_class(class_name)
      properties    = data.slice(*message_class.fields)

      message_class.new(properties.merge(HEADER_KEY => header))
    rescue Errors::Error
      raise
    rescue StandardError => e
      raise Errors::DecodeError, "could not build #{class_name || 'the message'} from the payload: #{e.class.name} - #{e.message}"
    end

    # Find a message class by name.
    #
    # @param class_name [String]
    # @return [Class] a SmartMessage::Base descendant
    # @raise [SmartMessage::Errors::UnknownMessageClass] when the name is
    #   not a constant, or names something that is not a message class
    def resolve_message_class(class_name)
      klass = constant_named(class_name) || anonymous_class_named(class_name)
      return klass if message_class?(klass)

      raise Errors::UnknownMessageClass, "#{class_name.inspect} is not a SmartMessage::Base subclass known to this process"
    end

    # @return [Boolean] true for a proper subclass of SmartMessage::Base
    def message_class?(klass)
      klass.is_a?(Class) && klass < SmartMessage::Base
    end

    # @return [Object, nil] the constant with that name, or nil
    def constant_named(class_name)
      return nil unless class_name.match?(/\A(::)?[A-Z]\w*(::[A-Z]\w*)*\z/)

      Object.const_get(class_name)
    rescue NameError
      nil
    end

    # Classes without a constant name (Class.new(SmartMessage::Base)) are
    # found among the loaded message classes by their to_s.
    def anonymous_class_named(class_name)
      SmartMessage::Base.descendants.find { |klass| klass.to_s == class_name }
    end

    def assert_channel_matches!(class_name, channel)
      return if channel.nil? || channel.to_s == class_name

      raise Errors::MessageClassMismatch,
            "payload on channel #{channel.to_s.inspect} names message class #{class_name.inspect}"
    end

    # @return [Hash] the header fields, Symbol keys
    def extract_header(data, fallback_header)
      header = data[HEADER_KEY] || fallback_header
      unless header.is_a?(Hash) && !header.empty?
        raise Errors::DecodeError, "payload has no #{HEADER_KEY} header"
      end

      header = header.transform_keys(&:to_sym)
      raise Errors::DecodeError, 'header does not name a message class' if header[:message_class].to_s.empty?

      header
    end

    # @return [Hash] the decoded data with Symbol keys at the top level
    def symbolize(data)
      raise Errors::DecodeError, "payload decoded to #{data.class}, expected a Hash" unless data.is_a?(Hash)

      data.transform_keys(&:to_sym)
    end
  end
end
