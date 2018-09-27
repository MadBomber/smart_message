# smart_message/plugin/stdout.rb
# frozen_string_literal: true

module SmartMessage
  class StdoutPlugin < SmartMessage::Plugin
    def config
      debug_me
    end

    def send(message)
      debug_me{[ :message ]}
    end

    def receive(message)
      debug_me{[ :message ]}
    end

    def displatch(message)
      debug_me{[ :message ]}
    end
  end # class StdoutPlugin < SmartMessage::Plugin
end # module SmartMessage
