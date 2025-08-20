# lib/smart_message/plugins.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Plugin configuration module for SmartMessage::Base
  # Handles transport, serializer, and logger configuration at both
  # class and instance levels
  module Plugins
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        # Class-level plugin storage
        class_variable_set(:@@transport, nil) unless class_variable_defined?(:@@transport)
        class_variable_set(:@@serializer, nil) unless class_variable_defined?(:@@serializer)
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
        @transport || self.class.class_variable_get(:@@transport) || SmartMessage::Transport.default
      else
        @transport = klass_or_instance
      end
    end

    def transport_configured?;  !transport_missing?;   end
    def transport_missing?
      # Check if transport is explicitly configured (without fallback to defaults)
      @transport.nil? && 
        (self.class.class_variable_get(:@@transport) rescue nil).nil?
    end
    def reset_transport;        @transport = nil;  end


    #########################################################
    ## instance-level serializer configuration

    def serializer(klass_or_instance = nil)
      if klass_or_instance.nil?
        # Return instance serializer, class serializer, or global configuration
        @serializer || self.class.class_variable_get(:@@serializer) || SmartMessage::Serializer.default
      else
        @serializer = klass_or_instance
      end
    end

    def serializer_configured?; !serializer_missing?;   end
    def serializer_missing?
      # Check if serializer is explicitly configured (without fallback to defaults)
      @serializer.nil? && 
        (self.class.class_variable_get(:@@serializer) rescue nil).nil?
    end
    def reset_serializer;       @serializer = nil;  end

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
          class_variable_get(:@@transport) || SmartMessage::Transport.default
        else
          class_variable_set(:@@transport, klass_or_instance)
        end
      end

      def transport_configured?;  !transport_missing?;   end
      def transport_missing?
        # Check if class-level transport is explicitly configured (without fallback to defaults)
        (class_variable_get(:@@transport) rescue nil).nil?
      end
      def reset_transport;       class_variable_set(:@@transport, nil);  end

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

      def logger_configured?;     !logger.nil?;   end
      def logger_missing?;         logger.nil?;   end
      def reset_logger;          class_variable_set(:@@logger, nil);  end

      #########################################################
      ## class-level serializer configuration

      def serializer(klass_or_instance = nil)
        if klass_or_instance.nil?
          # Return class-level serializer or fall back to global configuration
          class_variable_get(:@@serializer) || SmartMessage::Serializer.default
        else
          class_variable_set(:@@serializer, klass_or_instance)
        end
      end

      def serializer_configured?; !serializer_missing?;   end
      def serializer_missing?
        # Check if class-level serializer is explicitly configured (without fallback to defaults)
        (class_variable_get(:@@serializer) rescue nil).nil?
      end
      def reset_serializer;      class_variable_set(:@@serializer, nil);  end
    end
  end
end