# lib/smart_message/base.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB

require_relative './wrapper.rb'
require_relative './property_descriptions.rb'

module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash

    # Supports multi-level plugins for transport, serializer and logger.
    # Plugins can be made at the class level and at the instance level.
    @@transport   = nil
    @@serializer  = nil
    @@logger      = nil

    include Hashie::Extensions::Dash::PropertyTranslation

    include SmartMessage::PropertyDescriptions

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
    def initialize(**props, &block)
      # instance-level over ride of class plugins
      @transport   = nil
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
    ## Common instance methods

    # SMELL: How does the transport know how to decode a message before
    #        it knows the message class?  We need a wrapper around
    #        the entire message in a known serialization.  That
    #        wrapper would contain two properties: _sm_header and
    #        _sm_payload

    # NOTE: to publish a message it must first be encoded using a
    #       serializer.  The receive a subscribed to message it must
    #       be decoded via a serializer from the transport to be processed.
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

      raise Errors::TransportNotConfigured if transport_missing?
      transport.publish(_sm_header, payload)

      SS.add(_sm_header.message_class, 'publish')
      SS.get(_sm_header.message_class, 'publish')
    end # def publish



    #########################################################
    ## instance-level configuration

    # Configure the plugins for transport, serializer and logger
    def config(&block)
      instance_eval(&block) if block_given?
    end


    #########################################################
    ## instance-level transport configuration

    def transport(klass_or_instance = nil)
      klass_or_instance.nil? ? @transport || @@transport : @transport = klass_or_instance
    end

    def transport_configured?;  !transport.nil?;   end
    def transport_missing?;      transport.nil?;   end
    def reset_transport;        @transport = nil;  end


    #########################################################
    ## instance-level logger configuration

    def logger(klass_or_instance = nil)
      klass_or_instance.nil? ? @logger || @@logger : @logger = klass_or_instance
    end

    def logger_configured?;     !logger.nil?; end
    def logger_missing?;         logger.nil?; end
    def reset_logger;           @logger = nil;  end


    #########################################################
    ## instance-level serializer configuration

    def serializer(klass_or_instance = nil)
      klass_or_instance.nil? ? @serializer || @@serializer : @serializer = klass_or_instance
    end

    def serializer_configured?; !serializer.nil?;   end
    def serializer_missing?;     serializer.nil?;   end
    def reset_serializer;       @serializer = nil;  end


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
        class_eval(&block) if block_given?
      end


      #########################################################
      ## class-level transport configuration

      def transport(klass_or_instance = nil)
        klass_or_instance.nil? ? @@transport : @@transport = klass_or_instance
      end

      def transport_configured?;  !transport.nil?;   end
      def transport_missing?;      transport.nil?;   end
      def reset_transport;       @@transport = nil;  end


      #########################################################
      ## class-level logger configuration

      def logger(klass_or_instance = nil)
        klass_or_instance.nil? ? @@logger : @@logger = klass_or_instance
      end

      def logger_configured?;     !logger.nil?;   end
      def logger_missing?;         logger.nil?;   end
      def reset_logger;          @@logger = nil;  end


      #########################################################
      ## class-level serializer configuration

      def serializer(klass_or_instance = nil)
        klass_or_instance.nil? ? @@serializer : @@serializer = klass_or_instance
      end

      def serializer_configured?; !serializer.nil?;   end
      def serializer_missing?;     serializer.nil?;   end
      def reset_serializer;      @@serializer = nil;  end


      #########################################################
      ## class-level subscription management via the transport

      # Add this message class to the transport's catalog of
      # subscribed messages.  If the transport is missing, raise
      # an exception.
      def subscribe(process_method = nil)
        message_class   = whoami
        process_method  = message_class + '.process' if process_method.nil?

        # TODO: Add proper logging here

        raise Errors::TransportNotConfigured if transport_missing?
        transport.subscribe(message_class, process_method)
      end


      # Remove this process_method for this message class from the
      # subscribers list.
      def unsubscribe(process_method = nil)
        message_class   = whoami
        process_method  = message_class + '.process' if process_method.nil?
        # TODO: Add proper logging here

        transport.unsubscribe(message_class, process_method) if transport_configured?
      end


      # Remove this message class and all of its processing methods
      # from the subscribers list.
      def unsubscribe!
        message_class   = whoami

        # TODO: Add proper logging here

        transport.unsubscribe!(message_class) if transport_configured?
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

      ###################################################
      ## Business Logic resides in the #process method.

      # When a transport receives a subscribed to message it
      # creates an instance of the message and then calls
      # the process method on that instance.
      #
      # It is expected that SmartMessage classes over ride
      # the SmartMessage::Base#process method with appropriate
      # business logic to handle the received message content.
      def process(message_instance)
        raise Errors::NotImplemented
      end

    end # class << self
  end # class Base
end # module SmartMessage

require_relative 'header'
require_relative 'transport'
require_relative 'serializer'
require_relative 'logger'
