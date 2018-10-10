# lib/smart_message/base.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB

require_relative './wrapper.rb'

module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash

    # Supports multi-level plugins for serializer, broker and logger.
    # Plugins can be made at the class level and at the instance level.
    @@broker      = nil
    @@serializer  = nil
    @@logger      = nil

    include Hashie::Extensions::Dash::PropertyTranslation

    include Hashie::Extensions::Coercion
    include Hashie::Extensions::DeepMerge
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::MergeInitializer
    include Hashie::Extensions::MethodAccess

    # Common attrubutes for all messages
    # TODO: Need to change the SmartMessage::Header into a
    #       smartMessage::Wrapper concept where the message
    #       content is serialized into an element in the wrapper
    #       where the wrapper contains header/routing information
    #       in addition to the serialized message data.
    property :_sm_header

    # Constructor for a messsage definition that allows the
    # setting of initial values.
    def initialize(props = {}, &block)
      # instance-level over ride of class plugins
      @broker      = nil
      @serializer  = nil
      @logger      = nil

      attributes = {
        _sm_header: SmartMessage::Header.new(
          uuid:           SecureRandom.uuid,
          message_class:  self.class.to_s,
          published_at:   2,
          publisher_pid:  3
        )
      }.merge(props)

      super(attributes, &block)
    end


    ###################################################
    ## Business Logic resides in the #process method.

    # When a broker receives a subscribed to message it
    # creates an instance of the message and then calls
    # the process method on that instance.
    #
    # It is expected that SmartMessage classes over ride
    # the SmartMessage::Base#process method with appropriate
    # business logic to handle the received message content.
    def process
      debug_me{[ 'to_h' ]}
      raise Errors::NotImplemented
    end


    ###################################################
    ## Common instance methods

    # SMELL: How does the broker know how to decode a message before
    #        it knows the message class?  We need a wrapper around
    #        the entire message in a known serialization.  That
    #        wrapper would contain two properties: _sm_header and
    #        _sm_payload

    # NOTE: to publish a message it must first be encoded using a
    #       serializer.  The receive a subscribed to message it must
    #       be decoded via a serializer from the broker to be processed.
    def encode
      raise Errors::SerializerNotConfigured if serializer_missing?

      serializer.encode(self)
    end


    # NOTE: you publish instances; but, you subscribe/unsubscribe at
    #       the class-level
    def publish
      # TODO: move all of the _sm_ property processes into the wrapper
      _sm_header.published_at   = Time.now
      _sm_header.publisher_pid  = Process.pid

      payload = encode

      debug_me{[ :payload ]}

      raise Errors::BrokerNotConfigured if broker_missing?
      broker.publish(payload)

      debug_me
    end # def publish



    #########################################################
    ## instance-level configuration

    # Configure the plugins for broker, serializer and logger
    def config(&block)
      debug_me

      instance_eval(&block) if block_given?
    end


    #########################################################
    ## instance-level broker configuration

    def broker(klass_or_instance = nil)
      debug_me{[ :klass_or_instance ]}
      klass_or_instance.nil? ? @broker || @@broker : @broker = klass_or_instance
    end

    def broker_configured?;     !broker.nil?; end
    def broker_missing?;         broker.nil?; end


    #########################################################
    ## instance-level logger configuration

    def logger(klass_or_instance = nil)
      debug_me{[ :klass_or_instance ]}
      klass_or_instance.nil? ? @logger || @@logger : @logger = klass_or_instance
    end

    def logger_configured?;     !logger.nil?; end
    def logger_missing?;         logger.nil?; end


    #########################################################
    ## instance-level serializer configuration

    def serializer(klass_or_instance = nil)
      debug_me{[ :klass_or_instance ]}
      klass_or_instance.nil? ? @serializer || @@serializer : @serializer = klass_or_instance
    end

    def serializer_configured?; !serializer.nil?; end
    def serializer_missing?;     serializer.nil?; end


    #########################################################
    ## instance-level utility methods

    # return this class' name as a string
    def whoami
      self.class.to_s
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


    ###########################################################
    ## class methods

    class << self

      #########################################################
      ## class-level configuration

      def config(&block)
        debug_me

        class_eval(&block) if block_given?
      end


      #########################################################
      ## class-level broker configuration

      def broker(klass_or_instance = nil)
        klass_or_instance.nil? ? @@broker : @@broker = klass_or_instance
      end

      def broker_configured?;     !broker.nil?; end
      def broker_missing?;         broker.nil?; end


      #########################################################
      ## class-level logger configuration

      def logger(klass_or_instance = nil)
        klass_or_instance.nil? ? @@logger : @@logger = klass_or_instance
      end

      def logger_configured?;     !logger.nil?; end
      def logger_missing?;         logger.nil?; end


      #########################################################
      ## class-level serializer configuration

      def serializer(klass_or_instance = nil)
        klass_or_instance.nil? ? @@serializer : @@serializer = klass_or_instance
      end

      def serializer_configured?; !serializer.nil?; end
      def serializer_missing?;     serializer.nil?; end


      #########################################################
      ## class-level subscription management via the broker

      # Add this message class to the broker's catalog of
      # subscribed messages.  If the broker is missing, raise
      # an exception.
      def subscribe
        message_class = whoami
        debug_me{[ :message_class ]}

        raise Errors::BrokerNotConfigured if broker_missing?
        broker.subscribe(message_class)
      end


      # Remove this message class from the brokers catalog of
      # subscribed messages.  If the brocker is missing, no
      # reason to do anything.
      def unsubscribe
        message_class = whoami
        debug_me{[ :message_class ]}

        broker.unsubscribe(message_class) if broker_configured?
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


      # def self.process(payload)
      #   # TODO: allow configuration of serializer
      #   payload_hash = JSON.parse payload

      #   debug_me{[ :payload, :payload_hash ]}

      #   massage_instance = new(payload_hash)
      #   massage_instance.process # SMELL: maybe class-level process is sufficient
      # end

    end # class << self
  end # class Base
end # module SmartMessage

require_relative 'header'
require_relative 'broker'
require_relative 'serializer'
require_relative 'logger'
