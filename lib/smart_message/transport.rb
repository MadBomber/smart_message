# lib/smart_message/transport.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'transport/base'
require_relative 'transport/registry'
require_relative 'transport/stdout_transport'
require_relative 'transport/memory_transport'
require_relative 'transport/redis_transport'

module SmartMessage
  module Transport
    class << self
      def default
        # Check global configuration first, then fall back to framework default
        SmartMessage.configuration.default_transport
      end

      def registry
        @registry ||= Registry.new
      end

      def register(name, transport_class)
        registry.register(name, transport_class)
      end

      def get(name)
        registry.get(name)
      end

      def create(name, **options)
        transport_class = get(name)
        transport_class&.new(**options)
      end

      def available
        registry.list
      end
    end
  end
end