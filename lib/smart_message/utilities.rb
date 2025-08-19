# lib/smart_message/utilities.rb
# encoding: utf-8
# frozen_string_literal: true

require 'set'   # STDLIB

module SmartMessage
  # Utilities module for SmartMessage::Base
  # Provides utility methods for message introspection and debugging
  module Utilities
    def self.included(base)
      base.extend(ClassMethods)
    end

    #########################################################
    ## instance-level utility methods

    # return this class' name as a string
    def whoami
      self.class.to_s
    end

    # return this class' description
    def description
      self.class.description
    end

    # Clean accessor to the SmartMessage header object
    # Provides more intuitive API than _sm_header
    # Note: Renamed to avoid conflict with class-level header DSL
    def message_header
      _sm_header
    end

    # returns a collection of class Set that consists of
    # the symbolized values of the property names of the message
    # without the injected '_sm_' properties that support
    # the behind-the-sceens operations of SmartMessage.
    def fields
      to_h.keys
          .reject{|key| key.start_with?('_sm_')}
          .map{|key| key.to_sym}
          .to_set
    end

    # Pretty print the message content to STDOUT using amazing_print
    # @param pp_or_include_header [PP, Boolean] Either a PP printer object (from Ruby's pp library) 
    #                                           or include_header boolean (for our custom usage)
    # @param include_header [Boolean] Whether to include the SmartMessage header (default: false)
    def pretty_print(pp_or_include_header = nil, include_header: false)
      # Handle Ruby's PP library calling convention: pretty_print(pp_object)
      if pp_or_include_header.is_a?(Object) && pp_or_include_header.respond_to?(:text)
        # This is Ruby's PP library calling us - delegate to standard object pretty printing
        pp_or_include_header.text(self.inspect)
        return
      end
      
      # Handle our custom calling convention: pretty_print(include_header: true)
      if pp_or_include_header.is_a?(TrueClass) || pp_or_include_header.is_a?(FalseClass)
        include_header = pp_or_include_header
      end
      
      require 'amazing_print'
      
      if include_header
        # Show both header and content
        puts "Header:"
        puts "-" * 20
        
        # Get header data, converting to symbols and filtering out nils
        header_data = _sm_header.to_h
          .reject { |key, value| value.nil? }
        header_data = deep_symbolize_keys(header_data)
        ap header_data
        
        puts "\nContent:"
        puts "-" * 20
        
        # Get payload data (message properties excluding header)
        content_data = get_payload_data.reject { |key, value| value.nil? }
        content_data = deep_symbolize_keys(content_data)
        ap content_data
      else
        # Show only message content (excluding _sm_ properties and nil values)
        content_data = get_payload_data.reject { |key, value| value.nil? }
        content_data = deep_symbolize_keys(content_data)
        ap content_data
      end
    end

    private

    # Extract payload data (all properties except _sm_header)
    def get_payload_data
      self.class.properties.each_with_object({}) do |prop, hash|
        next if prop == :_sm_header
        hash[prop.to_sym] = self[prop]
      end
    end

    # Recursively convert all string keys to symbols in nested hashes and arrays
    def deep_symbolize_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = deep_symbolize_keys(value)
        end
      when Array
        obj.map { |item| deep_symbolize_keys(item) }
      else
        obj
      end
    end

    module ClassMethods
      #########################################################
      ## class-level description
      
      def description(desc = nil)
        if desc.nil?
          @description || "#{self.name} is a SmartMessage"
        else
          @description = desc.to_s
        end
      end

      #########################################################
      ## class-level utility methods

      # return this class' name as a string
      def whoami
        ancestors.first.to_s
      end

      # Return a Set of symbols representing each defined property of
      # this message class.
      def fields
        @properties.dup.delete_if{|item| item.to_s.start_with?('_sm_')}
      end
    end
  end
end