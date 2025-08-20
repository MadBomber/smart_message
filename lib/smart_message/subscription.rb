# lib/smart_message/subscription.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB

module SmartMessage
  # Subscription management module for SmartMessage::Base
  # Handles subscribe/unsubscribe operations and proc handler management
  module Subscription
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        # Registry for proc-based message handlers
        class_variable_set(:@@proc_handlers, {}) unless class_variable_defined?(:@@proc_handlers)
      end
    end

    module ClassMethods
      #########################################################
      ## proc handler management

      # Register a proc handler and return a unique identifier for it
      # @param message_class [String] The message class name
      # @param handler_proc [Proc] The proc to register
      # @return [String] Unique identifier for this handler
      def register_proc_handler(message_class, handler_proc)
        handler_id = "#{message_class}.proc_#{SecureRandom.hex(8)}"
        class_variable_get(:@@proc_handlers)[handler_id] = handler_proc
        handler_id
      end

      # Call a registered proc handler
      # @param handler_id [String] The handler identifier
      # @param wrapper [SmartMessage::Wrapper::Base] The message wrapper
      def call_proc_handler(handler_id, wrapper)
        handler_proc = class_variable_get(:@@proc_handlers)[handler_id]
        return unless handler_proc

        handler_proc.call(wrapper)
      end

      # Remove a proc handler from the registry
      # @param handler_id [String] The handler identifier to remove
      def unregister_proc_handler(handler_id)
        class_variable_get(:@@proc_handlers).delete(handler_id)
      end

      # Check if a handler ID refers to a proc handler
      # @param handler_id [String] The handler identifier
      # @return [Boolean] True if this is a proc handler
      def proc_handler?(handler_id)
        class_variable_get(:@@proc_handlers).key?(handler_id)
      end

      #########################################################
      ## class-level subscription management via the transport

      # Add this message class to the transport's catalog of
      # subscribed messages.  If the transport is missing, raise
      # an exception.
      #
      # @param process_method [String, Proc, nil] The processing method:
      #   - String: Method name like "MyService.handle_message" 
      #   - Proc: A proc/lambda that accepts (message_header, message_payload)
      #   - nil: Uses default "MessageClass.process" method
      # @param broadcast [Boolean, nil] Filter for broadcast messages (to: nil)
      # @param to [String, Array, nil] Filter for messages directed to specific entities
      # @param from [String, Array, nil] Filter for messages from specific entities
      # @param block [Proc] Alternative way to pass a processing block
      # @return [String] The identifier used for this subscription
      #
      # @example Using default handler 
      #   MyMessage.subscribe
      #
      # @example Using custom method name with filtering
      #   MyMessage.subscribe("MyService.handle_message", from: ['order-service'])
      #
      # @example Using a block with broadcast filtering
      #   MyMessage.subscribe(broadcast: true) do |header, payload|
      #     data = JSON.parse(payload)
      #     puts "Received broadcast: #{data}"
      #   end
      #
      # @example Entity-specific filtering (receives only messages from payment service)
      #   MyMessage.subscribe("OrderService.process", from: ['payment'])
      #
      # @example Explicit to filter 
      #   MyMessage.subscribe("AdminService.handle", to: 'admin', broadcast: false)
      def subscribe(process_method = nil, broadcast: nil, to: nil, from: nil, &block)
        message_class = whoami
        
        # Handle different parameter types
        if block_given?
          # Block was passed - use it as the handler
          handler_proc = block
          process_method = register_proc_handler(message_class, handler_proc)
        elsif process_method.respond_to?(:call)
          # Proc/lambda was passed as first parameter
          handler_proc = process_method
          process_method = register_proc_handler(message_class, handler_proc)
        elsif process_method.nil?
          # Use default handler
          process_method = message_class + '.process'
        end
        # If process_method is a String, use it as-is

        # Subscriber identity is derived from the process method (handler)
        # This ensures each handler gets its own DDQ scope per message class
        
        # Normalize string filters to arrays
        to_filter = normalize_filter_value(to)
        from_filter = normalize_filter_value(from)
        
        # Create filter options (no explicit subscriber identity needed)
        filter_options = {
          broadcast: broadcast,
          to: to_filter,
          from: from_filter
        }

        # Add proper logging
        logger = SmartMessage::Logger.default
        
        begin
          raise Errors::TransportNotConfigured if transport_missing?
          transport.subscribe(message_class, process_method, filter_options)
          
          # Log successful subscription
          handler_desc = block_given? || process_method.respond_to?(:call) ? " with block/proc handler" : ""
          logger.info { "[SmartMessage] Subscribed: #{self.name}#{handler_desc}" }
          logger.debug { "[SmartMessage::Subscription] Subscribed #{message_class} with filters: #{filter_options}" }
          
          process_method
        rescue => e
          logger.error { "[SmartMessage] Error in message subscription: #{e.class.name} - #{e.message}" }
          raise
        end
      end

      # Remove this process_method for this message class from the
      # subscribers list.
      # @param process_method [String, nil] The processing method identifier to remove
      #   - String: Method name like "MyService.handle_message" or proc handler ID
      #   - nil: Uses default "MessageClass.process" method
      def unsubscribe(process_method = nil)
        message_class   = whoami
        process_method  = message_class + '.process' if process_method.nil?
        # Add proper logging
        logger = SmartMessage::Logger.default
        
        begin
          if transport_configured?
            transport.unsubscribe(message_class, process_method)
            
            # If this was a proc handler, clean it up from the registry
            if proc_handler?(process_method)
              unregister_proc_handler(process_method)
            end
            
            # Log successful unsubscription
            logger.info { "[SmartMessage] Unsubscribed: #{self.name}" }
            logger.debug { "[SmartMessage::Subscription] Unsubscribed #{message_class} from #{process_method}" }
          end
        rescue => e
          logger.error { "[SmartMessage] Error in message unsubscription: #{e.class.name} - #{e.message}" }
          raise
        end
      end

      # Remove this message class and all of its processing methods
      # from the subscribers list.
      def unsubscribe!
        message_class   = whoami

        # TODO: Add proper logging here

        transport.unsubscribe!(message_class) if transport_configured?
      end

      ###################################################
      ## Business Logic resides in the #process method.

      # When a transport receives a subscribed to message it
      # creates an instance of the message and then calls
      # the process method on that instance.
      #
      # It is expected that SmartMessage classes over ride
      # the SmartMessage::Base#process method with appropriate
      # business logic to handle the received message content.
      def process(message_instance)
        raise Errors::NotImplemented
      end
    end
  end
end