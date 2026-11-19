# lib/smart_message/errors.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Errors
    # Root of every error SmartMessage raises on purpose
    class Error < RuntimeError; end

    # A message can't be very smart if it does not know how to
    # send and receive itself using a message transport
    class TransportNotConfigured < Error
      # @param class_name [String, #to_s] the message class with no transport
      # @return [TransportNotConfigured] an error naming the class and the fix
      def self.for(class_name)
        new("#{class_name} has no transport configured. Set one in the class " \
            "(transport SmartMessage::Transport.create(:memory)) or globally " \
            "(SmartMessage.configure { |config| config.transport = ... })")
      end
    end

    # The functionality has not be implemented
    class NotImplemented < Error; end

    # A message was received to which there is no subscription
    class ReceivedMessageNotSubscribed < Error; end

    # A received message names a class that is not a SmartMessage::Base
    # descendant known to this process
    class UnknownMessageClass < Error; end

    # A received payload arrived on a channel that belongs to a different
    # message class than the one named in its header
    class MessageClassMismatch < Error; end

    # A received payload is not a SmartMessage envelope
    class DecodeError < Error; end

    # A message could not be encoded by its serializer
    class SerializationError < Error; end

    # A transport could not be reached or used
    class TransportError < Error; end

    # A property name collides with the framework
    class ReservedPropertyName < ArgumentError; end

    # One or more property, header, or version validations failed.
    # +errors+ holds the same hashes that #validation_errors returns.
    class ValidationError < Error
      attr_reader :errors

      def initialize(message = nil, errors: [])
        @errors = errors
        super(message)
      end
    end

    # Publishing failed on every configured transport.
    # +result+ is the SmartMessage::PublishResult describing each failure.
    class PublishError < Error
      attr_reader :result

      def initialize(message = nil, result: nil)
        @result = result
        super(message)
      end
    end
  end
end
