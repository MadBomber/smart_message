# lib/smart_message/plug.rb
# frozen_string_literal: true

module SmartMessage
  # SmartMessage::Plugin provides the basis for the
  # framework that allows backend message brokers
  class Plugin
    DEFAULT_OPTIONS = {}
    def initialize(options={})
      @parameters = DEFAULT_OPTIONS.merge options
    end

    ###################################################
    ## Class methods

    def self.config(options={})
      debug_me{[ :options ]}
    end

    def self.send(message)
      debug_me{[ :message ]}
    end

    def self.receive(message)
      debug_me{[ :message ]}
    end

    def self.displatch(message)
      debug_me{[ :message ]}
    end

  end # class Plugin
end # module SmartMessage
