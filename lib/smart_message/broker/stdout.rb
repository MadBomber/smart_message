# smart_message/broker/stdout.rb
# encoding: utf-8
# frozen_string_literal: true

# brokers manage the interface between the smart message and the
# back end message delivery process.
module SmartMessage::Broker

  # A reference implementation of a broker used for testing
  class Stdout < SmartMessage::Broker::Base
    # Initialize
    # setting loopback to true will force a published message through
    # the receive process
    # setting file will declutter the STDOUT which during development
    # can get pretty hard to read with all of the background processes
    def initialize(loopback: false, file: STDOUT)
      @loopback_status  = loopback
      @file = file.is_a?(String) ? File.open(file, 'w') : file
      super
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
    def self.config
      debug_me(file: @file)
    end

    # put the encoded_message into the delievery system
    def publish(message_header, message_payload)
      @file.puts <<~EOS

        ===================================================
        == SmartMessage Payload Published by Broker::Stdout
        == #{message_header.inspect}
        == #{message_payload}
        ===================================================

      EOS

      receive(message_header, message_payload) if loopback?
    end


    def receive(message_header, message_payload)
      debug_me(file: @file){[ :message_header, :message_payload ]}

      @@dispatcher.route(message_header, message_payload)
    end


    # Add a non-duplicated message_class to the subscriptions Array
    def subscribe(message_class, process_method)
      @@dispatcher.add(message_class, process_method)
    end


    # remove a message_class and its process_method
    def unsubscribe(message_class, process_method)
      @@dispatcher.drop(message_class, process_method)
    end


    # remove a message_class and all of its process_methods
    def unsubscribe!(message_class, process_method)
      @@dispatcher.drop_all(message_class)
    end
  end # class Stdout < SmartMessage::Broker::Base
end # module SmartMessage::Broker

