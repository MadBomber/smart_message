# lib/smart_message/utilities.rb
# encoding: utf-8
# frozen_string_literal: true

require 'set' # STDLIB

module SmartMessage
  # Utilities module for SmartMessage::Base
  # Provides utility methods for message introspection and debugging
  module Utilities
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Copy nested Hashes, Arrays, and Strings so the copy shares no mutable
    # state with the original.  Other objects are returned as they are.
    def self.deep_copy(object)
      case object
      when Hash   then object.to_h { |key, value| [deep_copy(key), deep_copy(value)] }
      when Array  then object.map { |item| deep_copy(item) }
      when String then object.dup
      else             object
      end
    end

    # Recursively convert all Hash keys to Symbols in nested hashes and arrays
    def self.deep_symbolize_keys(object)
      case object
      when Hash  then object.to_h { |key, value| [key.to_sym, deep_symbolize_keys(value)] }
      when Array then object.map { |item| deep_symbolize_keys(item) }
      else            object
      end
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
    def message_header
      _sm_header
    end

    # @return [Set<Symbol>] the property names of this message, without the
    #   '_sm_' properties that support SmartMessage itself
    def fields
      self.class.fields
    end

    # @return [Hash] the message's own properties, without the header
    def payload_hash
      to_h.except(:_sm_header)
    end

    # Pretty print the message content using amazing_print when it is
    # installed, otherwise Ruby's pp.
    #
    # @param pp_or_include_header [PP, Boolean] Ruby's PP printer (when called
    #   by the pp library) or the include_header flag
    # @param include_header [Boolean] also show the SmartMessage header
    # @param out [IO] where to write (default $stdout)
    def pretty_print(pp_or_include_header = nil, include_header: false, out: $stdout)
      # Ruby's PP library calling convention: pretty_print(pp_object)
      if pp_or_include_header.respond_to?(:text)
        pp_or_include_header.text(inspect)
        return
      end

      include_header = pp_or_include_header if [true, false].include?(pp_or_include_header)

      if include_header
        out.write("Header:\n#{'-' * 20}\n")
        pretty_output(_sm_header.to_h.compact, out: out)
        out.write("\nContent:\n#{'-' * 20}\n")
      end

      pretty_output(payload_hash.compact, out: out)
    end

    private

    # Print data with amazing_print when available; it is a development
    # dependency, so fall back to the standard library pp otherwise.
    def pretty_output(data, out: $stdout)
      data = Utilities.deep_symbolize_keys(data)
      # amazing_print 3.x expects ActiveSupport::LogSubscriber to exist
      # whenever ActiveSupport is loaded.
      require 'active_support/log_subscriber' if defined?(::ActiveSupport)
      require 'amazing_print'
      out.puts data.ai
    rescue LoadError
      require 'pp'
      PP.pp(data, out)
    end

    module ClassMethods
      #########################################################
      ## class-level description

      def description(desc = nil)
        if desc.nil?
          own_setting(:description) || "#{name} is a SmartMessage"
        else
          set_setting(:description, desc.to_s)
        end
      end

      #########################################################
      ## class-level utility methods

      # return this class' name as a string
      def whoami
        to_s
      end

      # @return [Set<Symbol>] each defined property of this message class,
      #   without the '_sm_' properties
      def fields
        properties.reject { |name| name.to_s.start_with?('_sm_') }.to_set
      end
    end
  end
end
