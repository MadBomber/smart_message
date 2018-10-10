# smart_message/broker/stdout.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage::Broker
  class Stdout < SmartMessage::Broker::Base
    def config
      debug_me
    end

    def publish(encoded_message)
      debug_me

      STDOUT.puts <<~EOS

        ===================================================
        == SmartMessage Payload Published by Broker::Stdout
        == #{encoded_message}
        ===================================================

      EOS
    end

    def receive(message)
      debug_me{[ :message ]}
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
  end # class Stdout < SmartMessage::Broker::Base
end # module SmartMessage::Broker

