# lib/smart_message/transport/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # Base class for all transport implementations
    # This defines the standard interface that all transports must implement
    class Base
      attr_reader :options, :dispatcher

      def initialize(options = {})
        @options = default_options.merge(options)
        @dispatcher = options[:dispatcher] || SmartMessage::Dispatcher.new
        configure
      end

      # Transport-specific configuration
      def configure
        # Override in subclasses for specific setup
      end

      # Default options for this transport
      def default_options
        {}
      end

      # Publish a message
      # @param message_header [SmartMessage::Header] Message routing information
      # @param message_payload [String] Serialized message content
      def publish(message_header, message_payload)
        raise NotImplementedError, 'Transport must implement #publish'
      end

      # Subscribe to a message class
      # @param message_class [String] The message class name
      # @param process_method [String] The processing method identifier
      def subscribe(message_class, process_method)
        @dispatcher.add(message_class, process_method)
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

      # Receive and route a message (called by transport implementations)
      # @param message_header [SmartMessage::Header] Message routing information
      # @param message_payload [String] Serialized message content
      protected

      def receive(message_header, message_payload)
        @dispatcher.route(message_header, message_payload)
      end
    end
  end
end