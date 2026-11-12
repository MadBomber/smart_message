# lib/smart_message/logger/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Logger
    # The interface every SmartMessage logger implements.
    #
    #   logger.info("text")
    #   logger.info { "text built only when needed" }
    #   logger.info("text", order_id: 42)       # keyword data
    #   logger.level = :debug                    # Symbol, String, or Integer
    #   logger.debug?                            # => true
    #   logger.add(:warn, "text")
    #
    # A subclass implements #log(severity, message, data, &block), #level
    # and #level=.
    class Base
      LEVELS.each_with_index do |name, severity|
        # logger.debug / info / warn / error / fatal
        define_method(name) do |message = nil, **data, &block|
          log(severity, message, data, &block)
        end

        # logger.debug? / info? / warn? / error? / fatal?
        define_method(:"#{name}?") { level <= severity }
      end

      # Log at a severity given as a Symbol, String, or Integer.
      # @raise [ArgumentError] for an unknown level
      def add(severity, message = nil, **data, &block)
        log(SmartMessage::Logger.severity(severity), message, data, &block)
      end

      # @return [Integer] the lowest severity that is logged (0 = debug)
      def level
        raise NotImplementedError, "#{self.class.name} must implement #level"
      end

      def level=(_value)
        raise NotImplementedError, "#{self.class.name} must implement #level="
      end

      def close; end

      private

      # @param severity [Integer] index into LEVELS
      # @param message [String, nil]
      # @param data [Hash] keyword data given with the message
      def log(_severity, _message, _data)
        raise NotImplementedError, "#{self.class.name} must implement #log"
      end

      # The text to log: the block's value when a block was given.
      def resolve_message(message, &block)
        block ? block.call : message
      end
    end
  end
end
