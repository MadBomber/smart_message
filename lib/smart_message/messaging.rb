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
        
        # Get all configured transports (supports both single and multiple)
        transport_list = transports
        logger = self.class.logger || SmartMessage::Logger.default
        
        # Track publication results for each transport
        successful_transports = []
        failed_transports = []
        
        # Publish to each configured transport
        transport_list.each do |transport_instance|
          begin
            # Transport handles serialization - just pass the message instance
            logger.debug { "[SmartMessage::Messaging] About to call transport.publish on #{transport_instance.class.name.split('::').last}" }
            transport_instance.publish(self)
            logger.debug { "[SmartMessage::Messaging] transport.publish completed on #{transport_instance.class.name.split('::').last}" }
            
            successful_transports << transport_instance.class.name.split('::').last
          rescue => transport_error
            logger.error { "[SmartMessage] Transport #{transport_instance.class.name.split('::').last} failed: #{transport_error.class.name} - #{transport_error.message}" }
            failed_transports << { transport: transport_instance.class.name.split('::').last, error: transport_error }
          end
        end
        
        # Log overall publication results
        if successful_transports.any?
          logger.info { "[SmartMessage] Published: #{self.class.name} via #{successful_transports.join(', ')}" }
        end
        
        if failed_transports.any?
          logger.warn { "[SmartMessage] Failed transports for #{self.class.name}: #{failed_transports.map { |ft| ft[:transport] }.join(', ')}" }
        end
        
        # Raise error only if ALL transports failed
        if successful_transports.empty? && failed_transports.any?
          error_messages = failed_transports.map { |ft| "#{ft[:transport]}: #{ft[:error].message}" }.join('; ')
          raise Errors::PublishError, "All transports failed: #{error_messages}"
        end

        SS.add(_sm_header.message_class, 'publish')
        SS.get(_sm_header.message_class, 'publish')
      rescue => e
        (self.class.logger || SmartMessage::Logger.default).error { "[SmartMessage] Error in message publishing: #{e.class.name} - #{e.message}" }
        raise
      end
    end # def publish

  end
end