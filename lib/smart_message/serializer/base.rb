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
      # TODO: Add proper logging here
      raise ::SmartMessage::Errors::NotImplemented
    end

    def decode(payload)
      # TODO: Add proper logging here
      raise ::SmartMessage::Errors::NotImplemented
    end
  end # class Base
end # module SmartMessage::Serializer
