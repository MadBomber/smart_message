# smart_message/broker/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage::Broker
  # Establishes the common (base) functionality required of every broker
  class Base
    # Hash of Arrays.  Key is message class name.  Value is an Array
    # of methods to call to process the message.
    @@catalog = {}

    DEFAULT_OPTIONS = {}
    attr_accessor :parameters

    def initialize(options={})
      @parameters = DEFAULT_OPTIONS.merge options
    end

    def self.config(options, &block)
      self.new(options)
      yeild block if block.present?
    end

    # tell everyone about this message instance
    def publish(message_instance)
      debug_me{[ :message_instance ]}
      raise ::SmartMessage::Errors::NotImplemented
    end

    # ask tp be notified when a specific message class is received
    # using the specific processing method
    def subscribe(message_class, process_method)
      debug_me{[ :message_class ]}
      raise ::SmartMessage::Errors::NotImplemented
    end

    # Don't care about this message class any more
    def unsubscribe(message_class)
      debug_me{[ :message_class ]}
      raise ::SmartMessage::Errors::NotImplemented
    end

    # get a message payload from the broker
    def read(message_payload)
      debug_me{[ :message_payload ]}
      raise ::SmartMessage::Errors::NotImplemented
    end

    # put a message payload to the broker
    def write(message_payload)
      debug_me{[ :message_payload ]}
      raise ::SmartMessage::Errors::NotImplemented
    end

    # send this message payload to everyone who has subscribed to it
    def dispatch(message_class_string, message_payload)
      debug_me{[ :message_payload ]}
      raise ::SmartMessage::Errors::NotImplemented
    end

    private

    # store a subscribed message and its processing method in a catalog
    def insert_into_catalog(message_class, process_method)
      debug_me{[ :message_class ]}
      if @@catalog.include? message_class
        @@catalog[message_class] << process_method
      else
        @@catalog[message_class] = [process_method]
      end
    end

    # run through the catalog for the specific message class and
    # dispatch the message payload to all subscribers
    def dispatch_via_catalog(message_class, payload)
      debug_me{[ :message_class, :payload ]}

      raise ::SmartMessage::Errors::UnknownMessageClass if message_class.nil?

      if @@catalog.include? message_class
        @@catalog[message_class].each do |processor|
          # TODO: pass the payload on to each process
          #       in a seperate thread
          processor.call(payload)
        end
      else
        debug_me
        raise ::SmartMessage::Errors::ReceivedMessageNotSubscribed
      end
    end # def dispatch_via_catalog(message_class, payload)
  end # class StdoutBroker < SmartMessage::Broker
end # module SmartMessage::Broker
