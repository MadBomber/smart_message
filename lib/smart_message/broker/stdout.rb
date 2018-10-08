# smart_message/broker/stdout.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  class StdoutBroker < SmartMessage::Broker
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
  end # class StdoutBroker < SmartMessage::Broker
end # module SmartMessage
