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
      klass_or_instance.nil? ? @transport || self.class.class_variable_get(:@@transport) : @transport = klass_or_instance
    end

    def transport_configured?;  !transport.nil?;   end
    def transport_missing?;      transport.nil?;   end
    def reset_transport;        @transport = nil;  end

    #########################################################
    ## instance-level logger configuration

    def logger(klass_or_instance = nil)
      klass_or_instance.nil? ? @logger || self.class.class_variable_get(:@@logger) : @logger = klass_or_instance
    end

    def logger_configured?;     !logger.nil?; end
    def logger_missing?;         logger.nil?; end
    def reset_logger;           @logger = nil;  end

    #########################################################
    ## instance-level serializer configuration

    def serializer(klass_or_instance = nil)
      klass_or_instance.nil? ? @serializer || self.class.class_variable_get(:@@serializer) : @serializer = klass_or_instance
    end

    def serializer_configured?; !serializer.nil?;   end
    def serializer_missing?;     serializer.nil?;   end
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
        klass_or_instance.nil? ? class_variable_get(:@@transport) : class_variable_set(:@@transport, klass_or_instance)
      end

      def transport_configured?;  !transport.nil?;   end
      def transport_missing?;      transport.nil?;   end
      def reset_transport;       class_variable_set(:@@transport, nil);  end

      #########################################################
      ## class-level logger configuration

      def logger(klass_or_instance = nil)
        klass_or_instance.nil? ? class_variable_get(:@@logger) : class_variable_set(:@@logger, klass_or_instance)
      end

      def logger_configured?;     !logger.nil?;   end
      def logger_missing?;         logger.nil?;   end
      def reset_logger;          class_variable_set(:@@logger, nil);  end

      #########################################################
      ## class-level serializer configuration

      def serializer(klass_or_instance = nil)
        klass_or_instance.nil? ? class_variable_get(:@@serializer) : class_variable_set(:@@serializer, klass_or_instance)
      end

      def serializer_configured?; !serializer.nil?;   end
      def serializer_missing?;     serializer.nil?;   end
      def reset_serializer;      class_variable_set(:@@serializer, nil);  end
    end
  end
end