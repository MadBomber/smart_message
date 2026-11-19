# lib/smart_message/serializer/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Serializer
    # The standard super class for serializers.
    #
    # A subclass implements two private methods:
    #
    #   do_encode(message_hash)  # Hash with Symbol keys => String
    #   do_decode(payload)       # String => Hash
    #
    # Failures are raised as Errors::SerializationError (encode) or
    # Errors::DecodeError (decode); a serializer never returns anything but
    # a payload or a Hash.
    class Base
      # @return [Array<Class>] every loaded subclass
      def self.descendants
        subclasses.flat_map { |klass| [klass, *klass.descendants] }
      end

      # @param message_hash [Hash, #to_h] the message as a Hash
      # @return [String] the serialized payload
      # @raise [SmartMessage::Errors::SerializationError]
      def encode(message_hash)
        do_encode(message_hash.to_h)
      rescue SmartMessage::Errors::Error
        raise
      rescue StandardError => e
        raise SmartMessage::Errors::SerializationError,
              "#{self.class.name} could not encode: #{e.class.name} - #{e.message}"
      end

      # @param payload [String] a serialized payload
      # @return [Hash] the decoded message Hash
      # @raise [SmartMessage::Errors::DecodeError]
      def decode(payload)
        do_decode(payload)
      rescue SmartMessage::Errors::Error
        raise
      rescue StandardError => e
        raise SmartMessage::Errors::DecodeError,
              "#{self.class.name} could not decode: #{e.class.name} - #{e.message}"
      end

      private

      def do_encode(_message_hash)
        raise SmartMessage::Errors::NotImplemented, "#{self.class.name} must implement #do_encode"
      end

      def do_decode(_payload)
        raise SmartMessage::Errors::NotImplemented, "#{self.class.name} must implement #do_decode"
      end
    end
  end
end
