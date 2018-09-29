# lib/smart_message/broker.rb
# frozen_string_literal: true

module SmartMessage
  # SmartMessage::Broker provides the basis for the
  # framework that allows backend message brokers
  class Broker
    DEFAULT_OPTIONS = {}
    def initialize(options={})
      @parameters = DEFAULT_OPTIONS.merge options
    end

    ###################################################
    ## Class methods

    def self.config(options={})
      debug_me{[ :options ]}
    end

    def self.publish(message)
      debug_me{[ :message ]}
    end

    def self.receive(message)
      debug_me{[ :message ]}
    end

    def self.displatch(message)
      debug_me{[ :message ]}
    end

  end # class Broker
end # module SmartMessage
