# lib/smart_message/transport/base.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative '../circuit_breaker'

module SmartMessage
  module Transport
    # Base class for all transport implementations
    # This defines the standard interface that all transports must implement
    class Base
      include BreakerMachines::DSL

      attr_reader :options, :dispatcher, :serializer

      def initialize(**options)
        @options = default_options.merge(options)
        @dispatcher = options[:dispatcher] || SmartMessage::Dispatcher.new
        @serializer = options[:serializer] || default_serializer
        configure
        configure_transport_circuit_breakers
        
        logger.debug { "[SmartMessage::Transport::#{self.class.name.split('::').last}] Initialized with options: #{@options}" }
        logger.debug { "[SmartMessage::Transport::#{self.class.name.split('::').last}] Using serializer: #{@serializer.class.name}" }
      rescue => e
        logger&.error { "[SmartMessage] Error in transport initialization: #{e.class.name} - #{e.message}" }
        raise
      end
      
      private
      
      def logger
        @logger ||= SmartMessage::Logger.default
      end
      
      public

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

      # Publish a message with circuit breaker protection
      # @param message [SmartMessage::Base] The message instance to publish
      def publish(message)
        # Extract routing info from message header
        message_class = message._sm_header.message_class
        
        # Serialize the entire message (flat structure with _sm_header)
        serialized_message = encode_message(message)
        
        circuit(:transport_publish).wrap do
          do_publish(message_class, serialized_message)
        end
      rescue => e
        # Log the exception for debugging
        logger.error { "[SmartMessage] Error in transport publish: #{e.class.name} - #{e.message}" }
        
        # Re-raise if it's not a circuit breaker fallback
        raise unless e.is_a?(Hash) && e[:circuit_breaker]

        # Handle circuit breaker fallback
        handle_publish_fallback(e, message._sm_header.message_class, serialized_message)
      end

      # Template method for actual publishing (implement in subclasses)
      # @param message_class [String] The message class name (used for channel routing)
      # @param serialized_message [String] Complete serialized message content
      def do_publish(message_class, serialized_message)
        raise NotImplementedError, 'Transport must implement #do_publish'
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

      # Get transport circuit breaker statistics
      # @return [Hash] Circuit breaker statistics
      def transport_circuit_stats
        stats = {}

        [:transport_publish, :transport_subscribe].each do |circuit_name|
          begin
            if respond_to?(:circuit)
              breaker = circuit(circuit_name)
              if breaker
                stats[circuit_name] = {
                  status: breaker.status,
                  closed: breaker.closed?,
                  open: breaker.open?,
                  half_open: breaker.half_open?,
                  last_error: breaker.last_error,
                  opened_at: breaker.opened_at,
                  stats: breaker.stats
                }
              end
            end
          rescue => e
            stats[circuit_name] = { error: "Failed to get stats: #{e.message}" }
          end
        end

        stats
      end

      # Reset transport circuit breakers
      # @param circuit_name [Symbol] Optional specific circuit to reset
      def reset_transport_circuits!(circuit_name = nil)
        if circuit_name
          circuit(circuit_name)&.reset!
        else
          # Reset all transport circuits
          circuit(:transport_publish)&.reset!
          circuit(:transport_subscribe)&.reset!
        end
      end

      # Encode a message using the transport's serializer
      # @param message [SmartMessage::Base] The message to encode
      # @return [String] The serialized message
      def encode_message(message)
        # Update header with serializer info
        message._sm_header.serializer = @serializer.class.to_s
        
        # Serialize the entire message as a flat structure
        @serializer.encode(message.to_hash)
      end

      # Decode a message using the transport's serializer
      # @param serialized_message [String] The serialized message
      # @return [Hash] The decoded message data
      def decode_message(serialized_message)
        @serializer.decode(serialized_message)
      end

      # Receive and route a message (called by transport implementations)
      # @param message_class [String] The message class name
      # @param serialized_message [String] The serialized message content
      protected

      def receive(message_class, serialized_message)
        # Decode the message using transport's serializer
        decoded_data = decode_message(serialized_message)
        
        # Add defensive check for message_class type
        unless message_class.respond_to?(:constantize)
          logger.error { "[SmartMessage] Invalid message_class type: #{message_class.class.name} - #{message_class.inspect}" }
          logger.error { "[SmartMessage] Expected String, got: #{message_class.class.name}" }
          raise ArgumentError, "message_class must be a String, got #{message_class.class.name}"
        end
        
        # Reconstruct the message instance from flat structure
        message_class_obj = message_class.constantize
        # Convert string keys to symbols for keyword arguments
        symbol_data = decoded_data.transform_keys(&:to_sym)
        message = message_class_obj.new(**symbol_data)
        
        @dispatcher.route(message)
      rescue => e
        logger.error { "[SmartMessage] Error in transport receive: #{e.class.name} - #{e.message}" }
        logger.error { "[SmartMessage] message_class: #{message_class.inspect} (#{message_class.class.name})" }
        logger.error { "[SmartMessage] serialized_message length: #{serialized_message&.length}" }
        raise
      end

      # Configure circuit breakers for transport operations
      def configure_transport_circuit_breakers
        # Configure publish circuit breaker
        publish_config = SmartMessage::CircuitBreaker::DEFAULT_CONFIGS[:transport_publish]

        self.class.circuit :transport_publish do
          threshold failures: publish_config[:threshold][:failures],
                   within: publish_config[:threshold][:within].seconds
          reset_after publish_config[:reset_after].seconds

          # Use memory storage by default for transport circuits
          storage BreakerMachines::Storage::Memory.new

          # Fallback for publish failures - use DLQ fallback
          fallback SmartMessage::CircuitBreaker::Fallbacks.dead_letter_queue
        end

        # Configure subscribe circuit breaker
        subscribe_config = SmartMessage::CircuitBreaker::DEFAULT_CONFIGS[:transport_subscribe]

        self.class.circuit :transport_subscribe do
          threshold failures: subscribe_config[:threshold][:failures],
                   within: subscribe_config[:threshold][:within].seconds
          reset_after subscribe_config[:reset_after].seconds

          storage BreakerMachines::Storage::Memory.new

          # Fallback for subscribe failures - log and return error info
          fallback do |exception|
            {
              circuit_breaker: {
                circuit: :transport_subscribe,
                transport_type: self.class.name,
                state: 'open',
                error: exception.message,
                error_class: exception.class.name,
                timestamp: Time.now.iso8601,
                fallback_triggered: true
              }
            }
          end
        end
      end

      # Handle publish circuit breaker fallback
      # @param fallback_result [Hash] The circuit breaker fallback result
      # @param message_class [String] The message class name
      # @param serialized_message [String] The serialized message
      def handle_publish_fallback(fallback_result, message_class, serialized_message)
        # Log the circuit breaker activation
        logger.error { "[SmartMessage::Transport] Circuit breaker activated: #{self.class.name}" }
        logger.error { "[SmartMessage::Transport] Error: #{fallback_result[:circuit_breaker][:error]}" }
        logger.error { "[SmartMessage::Transport] Message: #{message_class}" }
        logger.info { "[SmartMessage::Transport] Sent to DLQ: #{fallback_result[:circuit_breaker][:sent_to_dlq]}" }

        # If message wasn't sent to DLQ by circuit breaker, send it now
        unless fallback_result.dig(:circuit_breaker, :sent_to_dlq)
          begin
            SmartMessage::DeadLetterQueue.default.enqueue(
              message_class,
              serialized_message,
              error: fallback_result.dig(:circuit_breaker, :error) || 'Circuit breaker activated',
              transport: self.class.name
            )
          rescue => dlq_error
            logger.warn { "[SmartMessage] Warning: Failed to store message in DLQ: #{dlq_error.message}" }
          end
        end

        # Return the fallback result to indicate failure
        fallback_result
      end
    end
  end
end
