# lib/smart_message/transport/registry.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  module Transport
    # Registry for transport implementations
    # Provides discovery and management of available transport adapters
    class Registry
      def initialize
        @transports = {}
        register_builtin_transports
      end

      # Register a transport class
      # @param name [Symbol, String] Transport identifier
      # @param transport_class [Class] Transport implementation class
      def register(name, transport_class)
        unless transport_class.ancestors.include?(SmartMessage::Transport::Base)
          raise ArgumentError, "Transport must inherit from SmartMessage::Transport::Base"
        end
        @transports[name.to_sym] = transport_class
      end

      # Get a transport class by name
      # @param name [Symbol, String] Transport identifier
      # @return [Class, nil] Transport class or nil if not found
      def get(name)
        @transports[name.to_sym]
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

      private

      def register_builtin_transports
        # Register built-in transports
        register(:stdout, SmartMessage::Transport::StdoutTransport)
        register(:memory, SmartMessage::Transport::MemoryTransport)
      end
    end
  end
end