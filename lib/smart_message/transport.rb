# lib/smart_message/transport.rb
# encoding: utf-8
# frozen_string_literal: true

require_relative 'transport/base'
require_relative 'transport/registry'
require_relative 'transport/stdout_transport'
require_relative 'transport/memory_transport'

module SmartMessage
  # Transport layer abstraction for SmartMessage
  module Transport
    class << self
      # Get the transport registry instance
      def registry
        @registry ||= Registry.new
      end

      # Register a transport adapter
      def register(name, transport_class)
        registry.register(name, transport_class)
      end

      # Get a transport by name
      def get(name)
        registry.get(name)
      end

      # Create a transport instance with options
      def create(name, options = {})
        transport_class = get(name)
        transport_class&.new(options)
      end

      # List all registered transports
      def available
        registry.list
      end
    end
  end
end
