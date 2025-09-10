# lib/smart_message/messaging.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Messaging module for SmartMessage::Base
  # Handles message publishing operations
  module Messaging


    # NOTE: you publish instances; but, you subscribe/unsubscribe at
    #       the class-level
    def publish
      begin
        # Validate the complete message before publishing (now uses overridden validate!)
        validate!
        
        # Update header with current publication info
        _sm_header.published_at   = Time.now
        _sm_header.publisher_pid  = Process.pid
        
        raise Errors::TransportNotConfigured if transport_missing?
        
        # Transport now handles serialization - just pass the message instance
        (self.class.logger || SmartMessage::Logger.default).debug { "[SmartMessage::Messaging] About to call transport.publish" }
        transport.publish(self)
        (self.class.logger || SmartMessage::Logger.default).debug { "[SmartMessage::Messaging] transport.publish completed" }
        
        # Log the message publish
        (self.class.logger || SmartMessage::Logger.default).info { "[SmartMessage] Published: #{self.class.name} via #{transport.class.name.split('::').last}" }

        SS.add(_sm_header.message_class, 'publish')
        SS.get(_sm_header.message_class, 'publish')
      rescue => e
        (self.class.logger || SmartMessage::Logger.default).error { "[SmartMessage] Error in message publishing: #{e.class.name} - #{e.message}" }
        raise
      end
    end # def publish

  end
end