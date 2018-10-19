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

      raise Errors::BrokerNotConfigured if broker_missing?
      broker.publish(_sm_header, payload)

      SS.add(_sm_header.message_class, 'publish')
    end # def publish



    #########################################################
    ## instance-level configuration

    # Configure the plugins for broker, serializer and logger
    def config(&block)
      instance_eval(&block) if block_given?
    end


    #########################################################
    ## instance-level broker configuration

    def broker(klass_or_instance = nil)
      klass_or_instance.nil? ? @broker || @@broker : @broker = klass_or_instance
    end

    def broker_configured?;     !broker.nil?;   end
    def broker_missing?;         broker.nil?;   end
    def reset_broker;           @broker = nil;  end


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
      ## class-level broker configuration

      def broker(klass_or_instance = nil)
        klass_or_instance.nil? ? @@broker : @@broker = klass_or_instance
      end

      def broker_configured?;     !broker.nil?;   end
      def broker_missing?;         broker.nil?;   end
      def reset_broker;          @@broker = nil;  end


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
      ## class-level subscription management via the broker

      # Add this message class to the broker's catalog of
      # subscribed messages.  If the broker is missing, raise
      # an exception.
      def subscribe(process_method=nil)
        message_class   = whoami
        process_method  = message_class + '.process' if process_method.nil?

        debug_me{[ :message_class, :process_method ]}

        raise Errors::BrokerNotConfigured if broker_missing?
        broker.subscribe(message_class, process_method)
      end


      # Remove this process_method for this message class from the
      # subscribers list.
      def unsubscribe(process_method=nil)
        message_class   = whoami
        process_method  = message_class + '.process' if process_method.nil?
        debug_me{[ :message_class, :process_method ]}

        broker.unsubscribe(message_class, process_method) if broker_configured?
      end


      # Remove this message class and all of its processing methods
      # from the subscribers list.
      def unsubscribe!
        message_class   = whoami

        debug_me{[ :message_class ]}

        broker.unsubscribe!(message_class) if broker_configured?
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

      # When a broker receives a subscribed to message it
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
require_relative 'broker'
require_relative 'serializer'
require_relative 'logger'
