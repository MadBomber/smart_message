# smart_message/broker/stdout.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage::Broker

  # A reference implementation of a broker used for testing
  class Stdout < SmartMessage::Broker::Base

    # Initialize
    def initialize
      @subscriptions = Array.new
    end


    # Is there anything about this broker that needs to be configured
    def config
      debug_me
    end

    # put the encoded_message into the delievery system
    def publish(encoded_message)
      debug_me

      STDOUT.puts <<~EOS

        ===================================================
        == SmartMessage Payload Published by Broker::Stdout
        == #{encoded_message}
        ===================================================

      EOS
    end


    def receive(encoded_message)
      debug_me{[ :encoded_message ]}
    end


    def displatch(encoded_message)
      debug_me{[ :encoded_message ]}
      # TODO: since the message is encoded and the broker does not
      #       know what the encoding is then how do we determine
      #       the message class?  That means that the payload has
      #       to be encoded in a way that is known which means that
      #       the header is actually a wrapper in a known encoding
      #       with a data element that is encoded via a serializer.
    end


    # Add a non-duplicated message_class to the subscriptions Array
    def subscribe(message_class)
      @subscriptions << message_class unless @subscriptions.include? message_class
    end


    # returns nil if the message_class is not in the subscriptions
    # otherwise returns the current subscriptions Array without the
    # message_class
    def unsubscribe(message_class)
      @subscriptions.reject!{|item| item == message_class}
    end


    # return the subscriptions Array
    def subscribers
      @subscriptions
    end
  end # class Stdout < SmartMessage::Broker::Base
end # module SmartMessage::Broker

