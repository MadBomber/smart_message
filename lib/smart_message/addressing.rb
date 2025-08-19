# lib/smart_message/addressing.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Addressing configuration module for SmartMessage::Base
  # Handles from, to, and reply_to addressing at both class and instance levels
  module Addressing
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        # Class-level addressing configuration - use a registry for per-class isolation
        class_variable_set(:@@addressing_registry, {}) unless class_variable_defined?(:@@addressing_registry)
      end
    end

    #########################################################
    ## instance-level addressing configuration

    def from(entity_id = nil)
      if entity_id.nil?
        @from || self.class.from
      else
        @from = entity_id
        # Update the header with the new value
        _sm_header.from = entity_id if _sm_header
      end
    end
    
    def from_configured?; !from.nil?; end
    def from_missing?;     from.nil?; end
    def reset_from;       
      @from = nil
      _sm_header.from = nil if _sm_header
    end

    def to(entity_id = nil)
      if entity_id.nil?
        @to || self.class.to
      else
        @to = entity_id
        # Update the header with the new value
        _sm_header.to = entity_id if _sm_header
      end
    end
    
    def to_configured?;   !to.nil?; end
    def to_missing?;       to.nil?; end
    def reset_to;         
      @to = nil
      _sm_header.to = nil if _sm_header
    end

    def reply_to(entity_id = nil)
      if entity_id.nil?
        @reply_to || self.class.reply_to
      else
        @reply_to = entity_id
        # Update the header with the new value
        _sm_header.reply_to = entity_id if _sm_header
      end
    end
    
    def reply_to_configured?; !reply_to.nil?; end
    def reply_to_missing?;     reply_to.nil?; end
    def reset_reply_to;       
      @reply_to = nil
      _sm_header.reply_to = nil if _sm_header
    end

    module ClassMethods
      #########################################################
      ## class-level addressing configuration
      
      # Helper method to normalize filter values (string -> array, nil -> nil)
      private def normalize_filter_value(value)
        case value
        when nil
          nil
        when String, Regexp
          [value]
        when Array
          # Validate that array contains only Strings and Regexps
          value.each do |item|
            unless item.is_a?(String) || item.is_a?(Regexp)
              raise ArgumentError, "Array filter values must be Strings or Regexps, got: #{item.class}"
            end
          end
          value
        else
          raise ArgumentError, "Filter value must be a String, Regexp, Array, or nil, got: #{value.class}"
        end
      end
      
      # Helper method to find addressing values in the inheritance chain
      private def find_addressing_value(field)
        # Start with current class
        current_class = self
        addressing_registry = class_variable_get(:@@addressing_registry)
        
        while current_class && current_class.respond_to?(:name)
          class_name = current_class.name || current_class.to_s
          
          # Check registry for this class
          result = addressing_registry.dig(class_name, field)
          return result if result
          
          # If we have a proper name but no result, also check the to_s version
          if current_class.name
            alternative_key = current_class.to_s
            result = addressing_registry.dig(alternative_key, field)
            return result if result
          end
          
          # Move up the inheritance chain
          current_class = current_class.superclass
          
          # Stop if we reach SmartMessage::Base or above
          break if current_class == SmartMessage::Base || current_class.nil?
        end
        
        nil
      end

      def from(entity_id = nil)
        class_name = self.name || self.to_s
        addressing_registry = class_variable_get(:@@addressing_registry)
        if entity_id.nil?
          # Try to find the value, checking inheritance chain
          result = find_addressing_value(:from)
          result
        else
          addressing_registry[class_name] ||= {}
          addressing_registry[class_name][:from] = entity_id
        end
      end
      
      def from_configured?; !from.nil?; end
      def from_missing?;     from.nil?; end
      def reset_from; 
        class_name = self.name || self.to_s
        addressing_registry = class_variable_get(:@@addressing_registry)
        addressing_registry[class_name] ||= {}
        addressing_registry[class_name][:from] = nil
      end

      def to(entity_id = nil)
        class_name = self.name || self.to_s
        addressing_registry = class_variable_get(:@@addressing_registry)
        if entity_id.nil?
          # Try to find the value, checking inheritance chain
          result = find_addressing_value(:to)
          result
        else
          addressing_registry[class_name] ||= {}
          addressing_registry[class_name][:to] = entity_id
        end
      end
      
      def to_configured?;   !to.nil?; end
      def to_missing?;       to.nil?; end
      def reset_to; 
        class_name = self.name || self.to_s
        addressing_registry = class_variable_get(:@@addressing_registry)
        addressing_registry[class_name] ||= {}
        addressing_registry[class_name][:to] = nil
      end

      def reply_to(entity_id = nil)
        class_name = self.name || self.to_s
        addressing_registry = class_variable_get(:@@addressing_registry)
        if entity_id.nil?
          # Try to find the value, checking inheritance chain
          result = find_addressing_value(:reply_to)
          result
        else
          addressing_registry[class_name] ||= {}
          addressing_registry[class_name][:reply_to] = entity_id
        end
      end
      
      def reply_to_configured?; !reply_to.nil?; end
      def reply_to_missing?;     reply_to.nil?; end
      def reset_reply_to; 
        class_name = self.name || self.to_s
        addressing_registry = class_variable_get(:@@addressing_registry)
        addressing_registry[class_name] ||= {}
        addressing_registry[class_name][:reply_to] = nil
      end
    end
  end
end