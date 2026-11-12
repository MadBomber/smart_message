# lib/smart_message/logger.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Logging for SmartMessage.
  #
  # Every component asks SmartMessage::Logger.default for its logger.  That
  # is the logger built from SmartMessage.configuration; with nothing
  # configured it is a Null logger, so nothing is written and no file is
  # created.
  #
  # The framework itself only ever calls the five level methods with a
  # block (logger.info { "..." }), so any object with the standard Ruby
  # Logger interface can be configured.  The loggers shipped here
  # (Lumberjack, Default, Null) share the richer interface defined by
  # SmartMessage::Logger::Base.
  module Logger
    LEVELS = %i[debug info warn error fatal].freeze

    class << self
      # The global logger
      def default
        @override || SmartMessage.configuration.default_logger
      end

      # Force a logger regardless of configuration (nil removes the override)
      def default=(logger)
        @override = logger
      end

      # Remove any override set with default=
      def reset!
        @override = nil
      end

      # Turn a level given as a Symbol, String, or Integer into its index
      # in LEVELS (the same numbers ::Logger uses for DEBUG..FATAL).
      #
      # @raise [ArgumentError] for a level that does not exist
      def severity(level)
        index = level.is_a?(Integer) ? level : LEVELS.index(level.to_s.downcase.to_sym)
        return index if index && index.between?(0, LEVELS.size - 1)

        raise ArgumentError, "Unknown log level: #{level.inspect}. Use one of #{LEVELS.inspect}"
      end
    end
  end
end
