# lib/smart_message/publish_result.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # What happened when a message was published: one outcome per transport.
  #
  #   result = message.publish
  #   result.success?        # every transport accepted the message
  #   result.partial?        # some did, some did not
  #   result.failed.each { |outcome| warn outcome.error.message }
  #
  # When every transport fails, #publish raises Errors::PublishError and the
  # result is available as error.result.
  class PublishResult
    # The outcome for one transport.  +error+ is nil on success.
    Outcome = Data.define(:transport, :error) do
      def success? = error.nil?
      def failure? = !success?

      # Short transport class name, for logs
      def transport_name
        transport.class.name.to_s.split('::').last
      end

      def to_h
        { transport: transport_name, success: success?, error: error&.message }
      end
    end

    attr_reader :message_class, :uuid, :outcomes

    def initialize(message_class:, uuid:, outcomes: [])
      @message_class = message_class
      @uuid          = uuid
      @outcomes      = outcomes
    end

    # Record one transport's outcome.
    def record(transport, error = nil)
      @outcomes << Outcome.new(transport: transport, error: error)
      self
    end

    def successful = outcomes.select(&:success?)
    def failed     = outcomes.select(&:failure?)
    def errors     = failed.map(&:error)

    # @return [Boolean] true when every transport accepted the message
    def success? = outcomes.any? && failed.empty?

    # @return [Boolean] true when no transport accepted the message
    def failure? = successful.empty?

    # @return [Boolean] true when some transports accepted it and some did not
    def partial? = successful.any? && failed.any?

    def to_h
      {
        message_class: message_class,
        uuid:          uuid,
        success:       success?,
        outcomes:      outcomes.map(&:to_h)
      }
    end
  end
end
