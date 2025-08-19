# lib/smart_message/messaging.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Messaging module for SmartMessage::Base
  # Handles message encoding and publishing operations
  module Messaging
    # SMELL: How does the transport know how to decode a message before
    #        it knows the message class?  We need a wrapper around
    #        the entire message in a known serialization.  That
    #        wrapper would contain two properties: _sm_header and
    #        _sm_payload

    # NOTE: to publish a message it must first be encoded using a
    #       serializer.  The receive a subscribed to message it must
    #       be decoded via a serializer from the transport to be processed.
    def encode
      raise Errors::SerializerNotConfigured if serializer_missing?

      serializer.encode(self)
    end

    # NOTE: you publish instances; but, you subscribe/unsubscribe at
    #       the class-level
    def publish
      # Validate the complete message before publishing (now uses overridden validate!)
      validate!
      
      # TODO: move all of the _sm_ property processes into the wrapper
      _sm_header.published_at   = Time.now
      _sm_header.publisher_pid  = Process.pid

      payload = encode

      raise Errors::TransportNotConfigured if transport_missing?
      transport.publish(_sm_header, payload)

      SS.add(_sm_header.message_class, 'publish')
      SS.get(_sm_header.message_class, 'publish')
    end # def publish
  end
end