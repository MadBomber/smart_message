# lib/smart_message/plugins.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Plugin configuration module for SmartMessage::Base
  # Handles transport and logger configuration at both
  # class and instance levels
  module Plugins
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        # Class-level plugin storage
        class_variable_set(:@@transport, nil) unless class_variable_defined?(:@@transport)
        class_variable_set(:@@logger, nil) unless class_variable_defined?(:@@logger)
      end
    end

    #########################################################
    ## instance-level configuration

    # Configure the plugins for transport, serializer and logger
    def config(&block)
      instance_eval(&block) if block_given?
    end

    #########################################################
    ## instance-level transport configuration

    def transport(klass_or_instance = nil)
      if klass_or_instance.nil?
        # Return instance transport, class transport, or global configuration
        # For backward compatibility, return first transport if array, otherwise single transport
        transport_value = @transport || self.class.class_variable_get(:@@transport) || SmartMessage::Transport.default
        transport_value.is_a?(Array) ? transport_value.first : transport_value
      else
        # Normalize to array for internal consistent handling
        @transport = Array(klass_or_instance)
        # Return the original value for backward compatibility with method chaining
        klass_or_instance
      end
    end

    def transport_configured?;  !transport_missing?;   end
    def transport_missing?
      # Check if transport is explicitly configured (without fallback to defaults)
      @transport.nil? && 
        (self.class.class_variable_get(:@@transport) rescue nil).nil?
    end
    def reset_transport;        @transport = nil;  end

    # Utility methods for working with transport collections
    def transports
      # Get the raw transport value (which is internally stored as array)
      raw_transport = @transport || self.class.class_variable_get(:@@transport) || SmartMessage::Transport.default
      # Always return as array for consistent handling
      raw_transport.is_a?(Array) ? raw_transport : Array(raw_transport)
    end

    def single_transport?
      transports.length == 1
    end

    def multiple_transports?
      transports.length > 1
    end

    module ClassMethods
      #########################################################
      ## class-level configuration

      def config(&block)
        class_eval(&block) if block_given?
      end

      #########################################################
      ## class-level transport configuration

      def transport(klass_or_instance = nil)
        if klass_or_instance.nil?
          # Return class-level transport or fall back to global configuration
          # For backward compatibility, return first transport if array, otherwise single transport
          transport_value = class_variable_get(:@@transport) || SmartMessage::Transport.default
          transport_value.is_a?(Array) ? transport_value.first : transport_value
        else
          # Normalize to array for internal consistent handling
          class_variable_set(:@@transport, Array(klass_or_instance))
          # Return the original value for backward compatibility with method chaining
          klass_or_instance
        end
      end

      def transport_configured?;  !transport_missing?;   end
      def transport_missing?
        # Check if class-level transport is explicitly configured (without fallback to defaults)
        (class_variable_get(:@@transport) rescue nil).nil?
      end
      def reset_transport;       class_variable_set(:@@transport, nil);  end

      # Utility methods for working with transport collections  
      def transports
        # Get the raw transport value (which is internally stored as array)
        raw_transport = class_variable_get(:@@transport) || SmartMessage::Transport.default
        # Always return as array for consistent handling
        raw_transport.is_a?(Array) ? raw_transport : Array(raw_transport)
      end

      def single_transport?
        transports.length == 1
      end

      def multiple_transports?
        transports.length > 1
      end

      #########################################################
      ## class-level logger configuration

      def logger(klass_or_instance = nil)
        if klass_or_instance.nil?
          # Return class-level logger or fall back to global configuration
          class_variable_get(:@@logger) || SmartMessage::Logger.default
        else
          class_variable_set(:@@logger, klass_or_instance)
        end
      end

      def logger_configured?;     !logger_missing?;   end
      def logger_missing?
        # Check if class-level logger is explicitly configured (without fallback to defaults)
        (class_variable_get(:@@logger) rescue nil).nil?
      end
      def reset_logger;          class_variable_set(:@@logger, nil);  end
    end
  end
end