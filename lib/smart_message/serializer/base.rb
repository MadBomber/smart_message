# lib/smart_message/serializer/base.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage::Serializer
  # the standard super class
  class Base
    # provide basic configuration
    def initialize
      # TODO: write this
    end

    def encode(message_instance)
      debug_me{[ :message_instance ]}
      raise ::Errors::NotImplemented
    end

    def decode(payload)
      debug_me{[ :payload ]}
      raise ::Errors::NotImplemented
    end
  end # class Base
end # module SmartMessage::Serializer
