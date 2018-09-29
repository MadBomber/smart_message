# lib/smart_message/base.rb
# frozen_string_literal: true

module SmartMessage
  # The foundation class for the smart message
  class Base < Hashie::Dash
    @@broker = nil

    include Hashie::Extensions::Dash::PropertyTranslation

    include Hashie::Extensions::Coercion
    include Hashie::Extensions::DeepMerge
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::MergeInitializer
    include Hashie::Extensions::MethodAccess

    # Connob attrubutes for all messages
    property :uuid,           default: nil
    property :message_class,  default: nil
    property :published_at,   default: nil
    property :publisher_pid,  default: nil

    def initialize(*args)
      super
    end

    ###################################################
    ## Common instance methods

    # def broker
    #   super
    # end

    # def broker=(value)
    #   super value
    # end

    # def broker?
    #   super
    # end

    def publish
      self.published_at   = Time.now
      self.publisher_pid  = Process.pid
      self.message_class  = self.class.to_s

      debug_me{[ :properties ]}

      # TODO: make serializer configurable instead of always JSON
      payload = self.to_json

      debug_me{[ :payload ]}

      if broker_configured?
        debug_me
        @@broker.publish(payload)
      end

      debug_me
    end # def publish

    def subscribe
      message_class = self.class.to_s
      debug_me{[ :message_class ]}

      @@broker.subscribe(message_class) if broker_configured?
    end

    def process
      debug_me
    end

    private

    def broker
      @@broker
    end

    def broker_configured?
      debug_me
      singleton_class.broker_configured?
    end

    ###################################################
    ## Class methods

    public

    class << self
      def broker
        @@broker
      end

      def broker_missing?
        @@broker.nil?
      end


      def config(broker_class=SmartMessage::StdoutBroker)
        @@broker = broker_class
        debug_me{[ '@@broker' ]}
      end

      def broker_configured?
        debug_me('XXXXXXXXXX')
        if broker_missing?
          debug_me
          raise Errors::NoBrokerConfigured
        else
          debug_me
          true
        end
      end

      def process(payload)
        # TODO: allow configuration of serializer
        payload_hash = JSON.parse payload

        debug_me{[ :payload, :payload_hash ]}

        massage_instance = new(payload_hash)
        massage_instance.process # SMELL: maybe class-level process is sufficient
      end

    end # class << self
  end # class Base
end # module SmartMessage
