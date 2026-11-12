# lib/smart_message/addressing.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Addressing configuration module for SmartMessage::Base
  # Handles from, to, and reply_to addressing at both class and instance levels.
  #
  # Class-level values are defaults, inherited by subclasses.  An instance
  # keeps its addressing in its header and nowhere else.
  module Addressing
    FIELDS = %i[from to reply_to].freeze

    # DSL context for header block processing
    class HeaderDSL
      def initialize(message_class)
        @message_class = message_class
      end

      FIELDS.each do |field|
        # Set the default value of the field for this message class
        define_method(field) { |entity_id| @message_class.public_send(field, entity_id) }
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    #########################################################
    ## instance-level addressing: reads and writes the header

    FIELDS.each do |field|
      # message.from          # => current value
      # message.from('svc')   # => sets it, returns the message for chaining
      define_method(field) do |entity_id = nil|
        return _sm_header[field] if entity_id.nil?

        _sm_header[field] = entity_id
        self
      end

      define_method(:"#{field}=")           { |entity_id| _sm_header[field] = entity_id }
      define_method(:"#{field}_configured?") { !_sm_header[field].nil? }
      define_method(:"#{field}_missing?")    { _sm_header[field].nil? }

      # Back to the class default
      define_method(:"reset_#{field}") { _sm_header[field] = self.class.public_send(field) }
    end

    module ClassMethods
      #########################################################
      ## Header DSL support

      # Header DSL block processor
      # Allows: header do; from "service"; to "target"; end
      def header(*args, &block)
        unless args.empty? && block
          raise ArgumentError,
                "header() at class level takes a block and no arguments. Use: header do; from 'value'; end"
        end

        HeaderDSL.new(self).instance_eval(&block)
      end

      #########################################################
      ## class-level addressing defaults

      FIELDS.each do |field|
        # MyMessage.from          # => this class's default, or its parent's
        # MyMessage.from('svc')   # => sets this class's default
        define_method(field) do |entity_id = nil|
          return setting(field) if entity_id.nil?

          set_setting(field, entity_id)
        end

        define_method(:"#{field}=")           { |entity_id| set_setting(field, entity_id) }
        define_method(:"#{field}_configured?") { !setting(field).nil? }
        define_method(:"#{field}_missing?")    { setting(field).nil? }
        define_method(:"reset_#{field}")       { clear_setting(field) }
      end
    end
  end
end
