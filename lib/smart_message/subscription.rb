# lib/smart_message/subscription.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom' # STDLIB

module SmartMessage
  # Subscription management module for SmartMessage::Base
  # Handles subscribe/unsubscribe operations and proc handler management
  module Subscription
    # Every registered block/proc handler, keyed by handler id.  One
    # registry for the whole process, because the dispatcher looks handlers
    # up by id alone.
    PROC_HANDLERS = Concurrent::Map.new

    # Handler ids for procs look like "MessageClass.proc_0123456789abcdef"
    PROC_HANDLER_ID = /\.proc_\h{16}\z/

    def self.included(base)
      base.extend(ClassMethods)
    end

    # @return [Boolean] true when +handler_id+ has the shape of a proc
    #   handler id, whether or not it is still registered
    def self.proc_handler_id?(handler_id)
      PROC_HANDLER_ID.match?(handler_id.to_s)
    end

    # Normalize a subscription filter: nil stays nil, a String or Regexp
    # becomes a one-element Array, an Array is checked and returned.
    #
    # @raise [ArgumentError] for any other type
    def self.normalize_filter_value(value)
      case value
      when nil            then nil
      when String, Regexp then [value]
      when Array
        value.each do |item|
          next if item.is_a?(String) || item.is_a?(Regexp)

          raise ArgumentError, "Array filter values must be Strings or Regexps, got: #{item.class}"
        end
        value
      else
        raise ArgumentError, "Filter value must be a String, Regexp, Array, or nil, got: #{value.class}"
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
        PROC_HANDLERS[handler_id] = handler_proc
        handler_id
      end

      # @return [Proc, nil] the registered proc for a handler id
      def proc_handler(handler_id)
        PROC_HANDLERS[handler_id]
      end

      # Call a registered proc handler
      # @param handler_id [String] The handler identifier
      def call_proc_handler(handler_id, message)
        proc_handler(handler_id)&.call(message)
      end

      # Remove a proc handler from the registry
      # @param handler_id [String] The handler identifier to remove
      def unregister_proc_handler(handler_id)
        PROC_HANDLERS.delete(handler_id)
      end

      # Remove every proc handler registered for a message class
      # @param message_class [String] The message class name
      def unregister_proc_handlers_for(message_class)
        prefix = "#{message_class}.proc_"
        PROC_HANDLERS.keys.each { |handler_id| PROC_HANDLERS.delete(handler_id) if handler_id.start_with?(prefix) }
      end

      # Check if a handler ID refers to a registered proc handler
      # @param handler_id [String] The handler identifier
      # @return [Boolean] True if this is a proc handler
      def proc_handler?(handler_id)
        PROC_HANDLERS.key?(handler_id)
      end

      #########################################################
      ## class-level subscription management via the transport

      # Subscribe this message class on every configured transport.
      #
      # @param process_method [String, Proc, nil] The processing method:
      #   - String: Method name like "MyService.handle_message"
      #   - Proc: A proc/lambda that accepts (message)
      #   - nil: Uses default "MessageClass.process" method
      # @param broadcast [Boolean, nil] Filter for broadcast messages (to: nil)
      # @param to [String, Regexp, Array, nil] Filter for messages directed to specific entities
      # @param from [String, Regexp, Array, nil] Filter for messages from specific entities
      # @param block [Proc] Alternative way to pass a processing block
      # @return [String] The identifier used for this subscription
      # @raise [SmartMessage::Errors::TransportNotConfigured] no transport
      # @raise [ArgumentError] when a named handler cannot be called
      #
      # @example Using default handler
      #   MyMessage.subscribe
      #
      # @example Using custom method name with filtering
      #   MyMessage.subscribe("MyService.handle_message", from: ['order-service'])
      #
      # @example Using a block with broadcast filtering
      #   MyMessage.subscribe(broadcast: true) do |message|
      #     handle(message)
      #   end
      def subscribe(process_method = nil, broadcast: nil, to: nil, from: nil, &block)
        message_class = whoami

        filter_options = {
          broadcast: broadcast,
          to:        Subscription.normalize_filter_value(to),
          from:      Subscription.normalize_filter_value(from)
        }

        raise Errors::TransportNotConfigured.for(message_class) if transport_missing?

        handler      = block || (process_method if process_method.respond_to?(:call))
        handler_id   = handler ? register_proc_handler(message_class, handler) : (process_method || "#{message_class}.process")
        check_named_handler!(handler_id) unless handler

        attempted = []
        begin
          transports.each do |transport_instance|
            # A String handler may already be subscribed (subscribe is
            # idempotent); only a subscription this call adds is rolled back.
            attempted << [transport_instance, !handler && already_subscribed?(transport_instance, message_class, handler_id)]
            transport_instance.subscribe(message_class, handler_id, filter_options)
          end
        rescue StandardError => e
          roll_back_subscription(attempted, message_class, handler_id)
          unregister_proc_handler(handler_id) if handler
          logger.error { "[SmartMessage] Error in message subscription: #{e.class.name} - #{e.message}" }
          raise
        end

        logger.info { "[SmartMessage] Subscribed: #{message_class}#{' with block/proc handler' if handler}" }
        logger.debug { "[SmartMessage::Subscription] Subscribed #{message_class} with filters: #{filter_options}" }

        handler_id
      end

      # Reject a handler given by name that can never be called, so the
      # mistake fails the subscribe instead of dead-lettering every message.
      # A class that is not defined yet is accepted: it is looked up when a
      # message arrives, so it may be defined after the subscription.
      #
      # @param handler_id [String] "Class.method"
      # @raise [ArgumentError] when it is not a "Class.method" String, or the
      #   class is defined without that class method
      def check_named_handler!(handler_id)
        unless handler_id.is_a?(String)
          raise ArgumentError, "A handler must be a \"Class.method\" String, a Proc, or a block; got #{handler_id.inspect}"
        end

        target_name, method_name = handler_id.split('.', 2)
        if method_name.to_s.empty?
          raise ArgumentError, "Handler #{handler_id.inspect} must name a class method as \"Class.method\""
        end

        target = begin
          Object.const_get(target_name)
        rescue NameError
          return handler_id
        end

        unless target.respond_to?(method_name)
          raise ArgumentError, "Handler #{handler_id.inspect}: #{target_name} has no class method #{method_name}"
        end

        if method_name == 'process' && target.method(:process).owner == Subscription::ClassMethods
          raise ArgumentError, "Handler #{handler_id.inspect} is not implemented: define `def self.process(message)` " \
                               "in #{target_name}, or subscribe with a block or another handler"
        end

        handler_id
      end

      # Remove one handler for this message class from every transport.
      # @param process_method [String, nil] The processing method identifier to remove
      #   - String: Method name like "MyService.handle_message" or proc handler ID
      #   - nil: Uses default "MessageClass.process" method
      def unsubscribe(process_method = nil)
        message_class    = whoami
        process_method ||= "#{message_class}.process"

        transports.each { |transport_instance| transport_instance.unsubscribe(message_class, process_method) }
        unregister_proc_handler(process_method)

        logger.info { "[SmartMessage] Unsubscribed: #{message_class} from #{process_method}" }
      end

      # Remove this message class and all of its processing methods
      # from every transport.
      def unsubscribe!
        message_class = whoami

        transports.each { |transport_instance| transport_instance.unsubscribe!(message_class) }
        unregister_proc_handlers_for(message_class)

        logger.info { "[SmartMessage] Unsubscribed all handlers: #{message_class}" }
      end

      private

      # Has this handler a subscription on the transport already?  A
      # transport that cannot say is treated as having one, so nothing that
      # may predate this call is removed.
      def already_subscribed?(transport_instance, message_class, handler_id)
        return true unless transport_instance.respond_to?(:subscribers)

        transport_instance.subscribers[message_class].any? { |subscription| subscription[:subscriber_id] == handler_id }
      rescue StandardError
        true
      end

      # Undo a subscribe that failed partway, on every transport it reached.
      def roll_back_subscription(attempted, message_class, handler_id)
        attempted.each do |transport_instance, preexisting|
          next if preexisting

          transport_instance.unsubscribe(message_class, handler_id)
        rescue StandardError => e
          logger.warn { "[SmartMessage] Could not roll back #{handler_id} on #{transport_instance.class.name}: #{e.message}" }
        end
      end

      public

      ###################################################
      ## Business Logic resides in the #process method.

      # The default handler.  A message class that subscribes without
      # naming a handler must define its own class-level process method:
      #
      #   class OrderMessage < SmartMessage::Base
      #     def self.process(message)
      #       # business logic
      #     end
      #   end
      def process(_message_instance)
        raise Errors::NotImplemented, "#{name}.process is not implemented"
      end
    end
  end
end
