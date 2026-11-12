# lib/smart_message/transport.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Transports move serialized messages between processes.
  #
  # Built in: :memory, :stdout, :file, :redis.  Extension gems register
  # their own:
  #
  #   SmartMessage::Transport.register(:nats, SmartMessage::Transport::NATS)
  #   SmartMessage::Transport.create(:nats, url: '...')
  module Transport
    class << self
      # The globally configured transport, or nil.  There is no framework
      # default: a transport has to be configured.
      def default
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

      # Build a registered transport.
      # @raise [ArgumentError] when no transport is registered under +name+
      def create(name, **options)
        transport_class = get(name)
        raise ArgumentError, "Unknown transport: #{name.inspect}. Available: #{available.inspect}" unless transport_class

        transport_class.new(**options)
      end

      def available
        registry.list
      end
    end
  end
end
