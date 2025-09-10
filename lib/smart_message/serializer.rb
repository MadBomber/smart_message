# lib/smart_message/serializer.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Serializer
    class << self
      def default
        # Return the framework's default serializer class
        # Note: Serialization is handled by transports, not messages
        SmartMessage::Serializer::Json
      end
    end
  end
end