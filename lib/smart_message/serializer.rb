# lib/smart_message/serializer.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Serializer
    class << self
      def default
        # Check global configuration first, then fall back to framework default
        SmartMessage.configuration.default_serializer
      end
    end
  end
end