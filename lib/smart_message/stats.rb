# lib/smart_message/stats.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # A small thread-safe counter store with multi-level keys.
  #
  #   SmartMessage::Stats.add('OrderMessage', 'publish')
  #   SmartMessage::Stats.get('OrderMessage', 'publish')   # => 1
  #
  # The framework counts 'publish' per message class, and 'routed',
  # 'processed', 'failed', and 'duplicate' per message class and handler.
  module Stats
    SEPARATOR = '+'

    @counters = Hash.new(0)
    @mutex    = Mutex.new

    class << self
      # @return [Hash] a copy of every counter
      def stat
        @mutex.synchronize { @counters.dup }
      end

      # @return [Integer] the count for a multi-level key
      def get(*levels)
        return 0 if levels.empty?

        @mutex.synchronize { @counters[key_for(levels)] }
      end

      # Increment a multi-level key and return the new count.
      def add(*levels, how_many: 1)
        return 0 if levels.empty?

        @mutex.synchronize { @counters[key_for(levels)] += how_many }
      end

      # Reset one key, or every key when called without arguments.
      def reset(*levels)
        @mutex.synchronize do
          levels.empty? ? @counters.clear : @counters.delete(key_for(levels))
        end
        0
      end

      def key_for(levels)
        levels.join(SEPARATOR)
      end

      def to_s
        stat.inspect
      end
    end
  end
end
