# lib/smart_message/base.rb
# encoding: utf-8
# frozen_string_literal: true

require 'securerandom'   # STDLIB

require_relative './dsl.rb'
require_relative './header.rb'


module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash

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
    # TODO: move this into a SmartMessage::Header object
    property :_sm_header

    def initialize(props = {}, &block)
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
    #        it knows the message class?

    def encode
      raise Errors::SerializerNotConfigured if serializer_missing?
      serializer.encode(self)
    end

    def publish
      _sm_header.published_at   = Time.now
      _sm_header.publisher_pid  = Process.pid

      debug_me{[ :properties ]}

      payload = encode

      debug_me{[ :payload ]}

      raise Errors::BrokerNotConfigured if broker_missing?
      broker.publish(payload)

      debug_me
    end # def publish


    def subscribe
      message_class = self.class.to_s
      debug_me{[ :message_class ]}

      broker.subscribe(message_class) if broker_configured?
    end


    def unsubscribe
      message_class = self.class.to_s
      debug_me{[ :message_class ]}

      broker.unsubscribe(message_class) if broker_configured?
    end


    def process
      debug_me
    end


    # TODO: allow instance configuration to over-ride the class
    #       class configuration.  e.g. Use @@broker when @broker.nil?
    def broker(klass_or_instance = nil)
      klass_or_instance.nil? ? @broker || @@broker : @broker = klass_or_instance
    end

    def serializer(klass_or_instance = nil)
      klass_or_instance.nil? ? @serializer || @@serializer : @serializer = klass_or_instance
    end

    def logger(klass_or_instance = nil)
      klass_or_instance.nil? ? @logger || @@logger : @logger = klass_or_instance
    end

    def broker_configured?; !broker.nil?; end
    def broker_missing?;     broker.nil?; end

    def serializer_configured?; !serializer.nil?; end
    def serializer_missing?;     serializer.nil?; end



    ###########################################################
    ## class methods

    def self.broker(klass_or_instance = nil)
      klass_or_instance.nil? ? @@broker : @@broker = klass_or_instance
    end

    def self.serializer(klass_or_instance = nil)
      klass_or_instance.nil? ? @@serializer : @@serializer = klass_or_instance
    end

    def self.logger(klass_or_instance = nil)
      klass_or_instance.nil? ? @@logger : @@logger = klass_or_instance
    end


    # class << self

      def self.broker_configured?; !broker.nil?; end
      def self.broker_missing?;     broker.nil?; end

      def self.serializer_configured?; !serializer.nil?; end
      def self.serializer_missing?;     serializer.nil?; end


      def self.config(
                  broker_class:     SmartMessage::Broker::Stdout,
                  serializer_class: SmartMessage::Serializer::JSON,
                  logger_class:     SmartMessage::Logger::Logger
                )
        broker    (broker_class)
        serializer(serializer_class)
        logger    (logger_class)
        debug_me{[ 'broker', 'serializer', 'logger' ]}
      end


      # def self.process(payload)
      #   # TODO: allow configuration of serializer
      #   payload_hash = JSON.parse payload

      #   debug_me{[ :payload, :payload_hash ]}

      #   massage_instance = new(payload_hash)
      #   massage_instance.process # SMELL: maybe class-level process is sufficient
      # end

    #  end # class << self
  end # class Base
end # module SmartMessage

require_relative 'header'
require_relative 'broker'
require_relative 'serializer'
require_relative 'logger'
