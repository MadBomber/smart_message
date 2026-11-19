# lib/smart_message/transport/registry.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # Registry for transport implementations
    # Provides discovery and management of available transport adapters
    class Registry
      # Built-in transports by class name, so a transport's dependencies
      # (the redis gem, for instance) load only when it is asked for.
      BUILTIN = {
        memory: 'SmartMessage::Transport::MemoryTransport',
        stdout: 'SmartMessage::Transport::StdoutTransport',
        file:   'SmartMessage::Transport::FileTransport',
        redis:  'SmartMessage::Transport::RedisTransport'
      }.freeze

      def initialize
        @transports = BUILTIN.dup
      end

      # Register a transport class
      # @param name [Symbol, String] Transport identifier
      # @param transport_class [Class] Transport implementation class
      # @raise [ArgumentError] unless it inherits from Transport::Base
      def register(name, transport_class)
        unless transport_class.is_a?(Class) && transport_class <= SmartMessage::Transport::Base
          raise ArgumentError, "Transport must inherit from SmartMessage::Transport::Base"
        end

        @transports[name.to_sym] = transport_class
      end

      # Get a transport class by name
      # @param name [Symbol, String] Transport identifier
      # @return [Class, nil] Transport class or nil if not found
      def get(name)
        entry = @transports[name.to_sym]
        entry.is_a?(String) ? Object.const_get(entry) : entry
      end

      # Check if a transport is registered
      # @param name [Symbol, String] Transport identifier
      # @return [Boolean]
      def registered?(name)
        @transports.key?(name.to_sym)
      end

      # List all registered transport names
      # @return [Array<Symbol>] List of transport identifiers
      def list
        @transports.keys
      end

      # Clear all registered transports
      def clear
        @transports.clear
      end
    end
  end
end
