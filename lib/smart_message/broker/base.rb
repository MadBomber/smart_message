# smart_message/broker/base.rb
# encoding: utf-8
# frozen_string_literal: true

# TODO: connect the broker to the dispatcher.

module SmartMessage::Broker
  # Establishes the common (base) functionality required of every broker
  class Base
    # The dispatcher manages subscriptions.  It is responsible for
    # routing incoming messages to their subscribed processing
    # methods.
    @@dispatcher    = SmartMessage::Dispatcher.new

    # placeholder in case there is a broker that needs to define
    # some default options
    DEFAULT_OPTIONS = {}

    attr_accessor :parameters

    def initialize(options={})
      @parameters = DEFAULT_OPTIONS.merge options
    end


    def dispatcher
      @@dispatcher
    end


    def subscribers
      @@dispatcher.subscribers
    end


    # tell everyone about this message instance
    def publish(message_header, message_payload)
      debug_me{[ :message_header, :message_payload ]}
      raise ::SmartMessage::Errors::NotImplemented
    end


    # ask tp be notified when a specific message class is received
    # using the specific processing method
    def subscribe(message_class, process_method)
      debug_me{[ :message_class, :process_method ]}
      # Insert broker specific code to handle subscription
      @@dispatcher.add(message_class, process_method)
    end


    # Don't care about this message class being handled by
    # this process
    def unsubscribe(message_class, process_method)
      debug_me{[ :message_class, :process_method ]}
      @@dispatcher.drop(message_class, process_method)
    end


    # Don't care about this message class
    def unsubscribe!(message_class)
      debug_me{[ :message_class, :process_method ]}
      @@dispatcher.drop_all(message_class)
    end


    # get a message payload from the broker
    def read(message_header, message_payload)
      debug_me{[ :message_header, :message_payload ]}
      raise ::SmartMessage::Errors::NotImplemented
    end


    # put a message payload to the broker
    def write(message_header, message_payload)
      debug_me{[ :message_header, :message_payload ]}
      raise ::SmartMessage::Errors::NotImplemented
    end
  end # class StdoutBroker < SmartMessage::Broker
end # module SmartMessage::Broker
