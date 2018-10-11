# smart_message/broker/stdout.rb
# encoding: utf-8
# frozen_string_literal: true

# brokers manage the interface between the smart message and the
# back end message delivery process.
module SmartMessage::Broker

  # A reference implementation of a broker used for testing
  class Stdout < SmartMessage::Broker::Base
    # Initialize
    def initialize(loopback: false)
      @subscriptions    = Array.new
      @loopback_status  = loopback
    end

    # loopback is a boolean that controls whether all published
    # messages are looped back into the system via the
    # subscription management framework.
    def loopback?
      @loopback_status
    end

    def loopback=(a_boolean)
      @loopback_status = a_boolean
    end

    # Is there anything about this broker that needs to be configured
    def config
      debug_me
    end

    # put the encoded_message into the delievery system
    def publish(encoded_message)
      STDOUT.puts <<~EOS

        ===================================================
        == SmartMessage Payload Published by Broker::Stdout
        == #{encoded_message}
        ===================================================

      EOS

      receive(encoded_message) if loopback?
    end


    def receive(encoded_message)
      debug_me{[ :encoded_message ]}
      header = fake_it(encoded_message)

      debug_me('before dispatch'){[ :header ]}

      dispatch(header['message_class'], encoded_message)
      debug_me('leaving receive')
    end

    # TODO: until the consider wrapper concept gets implemented
    #       fake it by assuming that the encoding is JSON.
    def fake_it(encoded_message)
      debug_me
      return JSON.parse(encoded_message)['_sm_header']
    end

    # NOTE: the dispatcher functional will become complicated and
    #       will reside in its on file soon.  For testing the
    #       framework this is sufficient.
    def dispatch(message_class_string, encoded_message)
      debug_me{[ :message_class_string, :encoded_message ]}

      klass = message_class_string.constantize

      debug_me{[ :klass ]}

      a_hash = klass.serializer.decode(encoded_message)

      debug_me{[ :a_hash ]}

      message_instance = klass.new(a_hash)

      debug_me{[ :message_instance ]}

      klass.process(message_instance)

    end # def dispatch(message_class_string, encoded_message)


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

