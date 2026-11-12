# lib/smart_message/messaging.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Messaging module for SmartMessage::Base
  # Handles message publishing operations
  module Messaging
    # Publish this message on every configured transport.
    #
    # NOTE: you publish instances; but, you subscribe/unsubscribe at
    #       the class-level
    #
    # Each transport is tried independently.  A transport that fails is
    # recorded in the result and the message is written to the dead letter
    # queue with that transport's name.
    #
    # @return [SmartMessage::PublishResult] one outcome per transport.  Check
    #   #success? or #partial? when publishing to more than one transport.
    # @raise [SmartMessage::Errors::ValidationError] the message is invalid
    # @raise [SmartMessage::Errors::TransportNotConfigured] no transport
    # @raise [SmartMessage::Errors::PublishError] every transport failed;
    #   error.result holds the outcomes
    def publish
      validate!
      raise Errors::TransportNotConfigured, "#{self.class.name} has no transport configured" if transport_missing?

      _sm_header.published_at  = Time.now
      _sm_header.publisher_pid = Process.pid

      result = PublishResult.new(message_class: _sm_header.message_class, uuid: _sm_header.uuid)
      transports.each { |transport_instance| result.record(transport_instance, publish_to(transport_instance)) }

      report_publish(result)
      result
    end

    private

    # Publish on one transport.
    #
    # @return [StandardError, nil] the failure, or nil on success
    def publish_to(transport_instance)
      transport_instance.publish(self)
      nil
    rescue StandardError => e
      logger.error do
        "[SmartMessage] Transport #{transport_instance.class.name} failed to publish " \
          "#{self.class.name}: #{e.class.name} - #{e.message}"
      end
      dead_letter_failed_publish(transport_instance, e)
      e
    end

    # A failed publish is never dropped silently: it goes to the DLQ.  If
    # the DLQ write fails too, that is logged at error level.
    def dead_letter_failed_publish(transport_instance, error)
      SmartMessage::DeadLetterQueue.default.enqueue(
        self,
        error:       "#{error.class.name}: #{error.message}",
        transport:   transport_instance.class.name,
        stack_trace: error.backtrace&.join("\n")
      )
    rescue StandardError => e
      logger.error { "[SmartMessage] Failed to store unpublished message in DLQ: #{e.class.name} - #{e.message}" }
    end

    # Log the outcome, count it, and raise when nothing was delivered.
    def report_publish(result)
      if result.failure?
        details = result.failed.map { |outcome| "#{outcome.transport_name}: #{outcome.error.message}" }.join('; ')
        raise Errors::PublishError.new("All transports failed for #{self.class.name}: #{details}", result: result)
      end

      SmartMessage::Stats.add(_sm_header.message_class, 'publish')
      names = result.successful.map(&:transport_name).join(', ')
      logger.info { "[SmartMessage] Published: #{self.class.name} via #{names}" }
      return unless result.partial?

      logger.warn do
        "[SmartMessage] Failed transports for #{self.class.name}: #{result.failed.map(&:transport_name).join(', ')}"
      end
    end
  end
end
