# lib/smart_message/transport/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # Base class for all transport implementations.
    #
    # == The transport contract
    #
    # A transport subclass implements:
    #
    #   do_publish(message_class, serialized_message)
    #     Deliver the bytes.  Raise on failure; never return a failure value.
    #
    # and may override:
    #
    #   configure            set up state (called from initialize)
    #   default_options      Hash merged under the caller's options
    #   default_serializer   serializer instance (default Serializer::Json)
    #   subscribe / unsubscribe / unsubscribe!
    #                        call super, then start or stop listening
    #   connected?           true while the transport can be used
    #   connect              (re)open connections
    #   disconnect           stop threads and close what the transport
    #                        opened; idempotent; never closes an IO it was
    #                        handed (such as $stdout)
    #
    # Inbound bytes are handed to #receive(message_class, serialized_message),
    # which decodes them and routes the message to subscribed handlers.
    # Pass nil for message_class when the transport has no channels.
    class Base
      attr_reader :options, :dispatcher, :serializer

      # @param options [Hash] transport options, plus:
      #   :dispatcher       a SmartMessage::Dispatcher to share
      #   :serializer       a serializer instance
      #   :circuit_breaker  { transport_publish: {...}, message_processor: {...} }
      def initialize(**options)
        @options    = default_options.merge(options)
        breakers    = @options[:circuit_breaker] || {}
        @dispatcher = @options[:dispatcher] || SmartMessage::Dispatcher.new(breakers)
        @serializer = @options[:serializer] || default_serializer

        @publish_circuit = SmartMessage::CircuitBreaker.build(
          "transport_publish:#{self.class.name}:#{object_id}",
          SmartMessage::CircuitBreaker.config_for(:transport_publish, breakers[:transport_publish])
        )

        configure

        logger.debug { "[#{self.class.name}] Initialized with serializer #{@serializer.class.name}" }
      end

      # Transport-specific configuration
      def configure
        # Override in subclasses for specific setup
      end

      # Default options for this transport
      def default_options
        {}
      end

      # Default serializer for this transport (override in subclasses)
      def default_serializer
        SmartMessage::Serializer::Json.new
      end

      # Publish a message, protected by this transport's circuit breaker.
      #
      # @param message [SmartMessage::Base] The message instance to publish
      # @return [true]
      # @raise [SmartMessage::Errors::SerializationError] the message could not be encoded
      # @raise [BreakerMachines::CircuitOpenError] the transport has failed
      #   repeatedly and its circuit is open
      # @raise [StandardError] whatever #do_publish raised
      def publish(message)
        message_class      = message._sm_header.message_class
        serialized_message = encode_message(message)

        @publish_circuit.wrap { do_publish(message_class, serialized_message) }
        true
      end

      # Template method for actual publishing (implement in subclasses)
      # @param message_class [String] The message class name (used for channel routing)
      # @param serialized_message [String] Complete serialized message content
      def do_publish(message_class, serialized_message)
        raise SmartMessage::Errors::NotImplemented, "#{self.class.name} must implement #do_publish"
      end

      # Subscribe to a message class
      # @param message_class [String] The message class name
      # @param process_method [String] The processing method identifier
      # @param filter_options [Hash] Optional filtering criteria
      def subscribe(message_class, process_method, filter_options = {})
        @dispatcher.add(message_class, process_method, filter_options)
      end

      # Unsubscribe from a specific message class and process method
      # @param message_class [String] The message class name
      # @param process_method [String] The processing method identifier
      def unsubscribe(message_class, process_method)
        @dispatcher.drop(message_class, process_method)
      end

      # Unsubscribe from all process methods for a message class
      # @param message_class [String] The message class name
      def unsubscribe!(message_class)
        @dispatcher.drop_all(message_class)
      end

      # Get current subscriptions
      def subscribers
        @dispatcher.subscribers
      end

      # Check if transport is connected/available
      def connected?
        true
      end

      # Connect to transport (if applicable)
      def connect
        # Override in subclasses if connection setup is needed
      end

      # Disconnect from transport (if applicable)
      def disconnect
        # Override in subclasses if cleanup is needed
      end

      # Get the publish circuit breaker's statistics
      # @return [Hash] { transport_publish: { status:, closed:, open:, ... } }
      def transport_circuit_stats
        breaker = @publish_circuit
        {
          transport_publish: {
            status:     breaker.status_name,
            closed:     breaker.closed?,
            open:       breaker.open?,
            half_open:  breaker.half_open?,
            last_error: SmartMessage::CircuitBreaker.last_error_of(breaker),
            stats:      breaker.stats.to_h
          }
        }
      end

      # Close the publish circuit and forget its failures.
      def reset_transport_circuits!(_circuit_name = nil)
        @publish_circuit.hard_reset!
        nil
      end

      # Encode a message using the transport's serializer
      # @param message [SmartMessage::Base] The message to encode
      # @return [String] The serialized message
      def encode_message(message)
        SmartMessage::Envelope.encode(message, @serializer)
      end

      # Decode a payload using the transport's serializer
      # @param serialized_message [String] The serialized message
      # @param channel [String, nil] the message class it arrived for
      # @return [SmartMessage::Base] The decoded message
      def decode_message(serialized_message, channel: nil)
        SmartMessage::Envelope.decode(serialized_message, serializer: @serializer, channel: channel)
      end

      protected

      # Receive and route a message (called by transport implementations).
      #
      # A payload that cannot be decoded is stored in the dead letter queue
      # and the error is raised to the caller.
      #
      # @param message_class [String, nil] The class (channel) the payload
      #   arrived for; nil when the transport has no channels
      # @param serialized_message [String] The serialized message content
      def receive(message_class, serialized_message)
        message = decode_message(serialized_message, channel: message_class)
        @dispatcher.route(message)
      rescue SmartMessage::Errors::Error => e
        logger.error { "[#{self.class.name}] Could not receive #{message_class.inspect}: #{e.class.name} - #{e.message}" }
        dead_letter_undecodable(message_class, serialized_message, e) if dead_letter_on_receive_error?(e)
        raise
      end

      # Should a payload that failed in #receive be stored in the dead letter
      # queue?  Transports whose channels carry other programs' messages
      # override this.
      def dead_letter_on_receive_error?(_error)
        true
      end

      private

      def logger
        SmartMessage::Logger.default
      end

      def dead_letter_undecodable(message_class, serialized_message, error)
        SmartMessage::DeadLetterQueue.default.enqueue_raw(
          message_class: message_class || 'Unknown',
          payload:       serialized_message,
          error_info:    { error: "#{error.class.name}: #{error.message}", transport: self.class.name }
        )
      rescue StandardError => e
        logger.error { "[#{self.class.name}] Could not store undecodable payload in DLQ: #{e.class.name} - #{e.message}" }
      end
    end
  end
end
