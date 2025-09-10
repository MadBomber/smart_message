# smart_message/lib/smart_message/errors.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Errors
    # A message can't be very smart if it does not know how to
    # send and receive itself using a message transport
    class TransportNotConfigured < RuntimeError; end

    # A message can't be very smart if it does not know how to
    # send and receive itself using a message transport
    class TransportNotConfigured < RuntimeError; end

    # A message can't be very smart if it does not know how to
    # encode and decode itself using a message serializer
    class SerializerNotConfigured < RuntimeError; end

    # The functionality has not be implemented
    class NotImplemented < RuntimeError; end

    # A message was received to which there is no subscription
    class ReceivedMessageNotSubscribed < RuntimeError; end

    # A received message is of an unknown class
    class UnknownMessageClass < RuntimeError; end

    # A property validation failed
    class ValidationError < RuntimeError; end

    # Publishing failed on all configured transports
    class PublishError < RuntimeError; end

  end
end
