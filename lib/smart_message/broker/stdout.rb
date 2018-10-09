# smart_message/broker/stdout.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage::Broker
  class Stdout < SmartMessage::Broker::Base
    def config
      debug_me
    end

    def publish(message)
      debug_me{[ :message ]}
    end

    def receive(message)
      debug_me{[ :message ]}
    end

    def displatch(message)
      debug_me{[ :message ]}
    end
  end # class Stdout < SmartMessage::Broker::Base
end # module SmartMessage::Broker

