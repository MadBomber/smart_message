# lib/smart_message/configuration.rb
# encoding: utf-8
# frozen_string_literal: true

require 'etc'

module SmartMessage
  # Global configuration for the SmartMessage framework.
  #
  # Message classes use these values unless they set their own.
  #
  #   SmartMessage.configure do |config|
  #     config.transport = SmartMessage::Transport::MemoryTransport.new
  #     config.logger    = 'log/my_app.log'
  #     config.log_level = :debug
  #     config.dlq_path  = '/var/lib/my_app/dead_letters.jsonl'
  #   end
  #
  # == Logging
  #
  # No configuration means NO LOGGING: nothing is written and no file is
  # created.  +logger+ accepts:
  #
  #   nil                 no logging (the default)
  #   :default            the Lumberjack logger writing to log/smart_message.log
  #   a String path       the Lumberjack logger writing to that file
  #   STDOUT / STDERR     the Lumberjack logger writing to the console
  #   any logger object   used as it is (Rails.logger, Logger.new(...), ...)
  #
  # The log_* settings shape the Lumberjack logger:
  #
  #   config.log_level           = :debug     # :debug, :info, :warn, :error, :fatal
  #   config.log_format          = :json      # :text or :json
  #   config.log_include_source  = true       # add file:line of the caller
  #   config.log_structured_data = true       # keep keyword data on log calls
  #   config.log_colorize        = true       # colour console output
  #   config.log_options         = {          # rotation
  #     roll_by_size: true, max_file_size: 50 * 1024 * 1024, keep_files: 10
  #   }
  #
  # The logger is built once, when it is first needed, and rebuilt only
  # after one of these settings changes.
  #
  # == Transport
  #
  # There is no default transport.  Set one here, or on each message class.
  #
  # == Dead letter queue
  #
  # +dlq_path+ is the file the default DeadLetterQueue writes to.  It
  # defaults to $SMART_MESSAGE_DLQ_PATH, else
  # $XDG_STATE_HOME/smart_message/dead_letters.jsonl
  # (~/.local/state/smart_message/dead_letters.jsonl), and is always
  # absolute: it never depends on the working directory.
  #
  # == Dispatcher
  #
  #   config.dispatcher_max_threads = 10     # handler threads per dispatcher
  #   config.dispatcher_max_queue   = 1_000  # messages that may wait for a thread
  #   config.shutdown_timeout       = 5      # seconds SmartMessage.shutdown waits
  class Configuration
    LOG_SETTINGS = %i[log_level log_format log_include_source log_structured_data log_colorize log_options].freeze

    DEFAULT_DISPATCHER_MAX_THREADS = [Etc.nprocessors * 2, 4].max
    DEFAULT_DISPATCHER_MAX_QUEUE   = 1_000

    attr_accessor :transport, :dispatcher_max_threads, :dispatcher_max_queue, :shutdown_timeout
    attr_reader   :logger, :dlq_path, *LOG_SETTINGS

    # The file the default dead letter queue uses when none is configured.
    #
    # @param env [Hash] the environment to read (injectable for tests)
    # @return [String] an absolute path
    def self.default_dlq_path(env = ENV)
      explicit = env['SMART_MESSAGE_DLQ_PATH']
      return File.expand_path(explicit) unless explicit.to_s.empty?

      state_home = env['XDG_STATE_HOME']
      state_home = File.join(Dir.home, '.local', 'state') if state_home.to_s.empty?
      File.join(File.expand_path(state_home), 'smart_message', 'dead_letters.jsonl')
    end

    def initialize
      reset!
    end

    # Reset configuration to defaults
    def reset!
      @logger                 = nil
      @transport              = nil
      @log_level              = nil
      @log_format             = nil
      @log_include_source     = nil
      @log_structured_data    = nil
      @log_colorize           = nil
      @log_options            = {}
      @dlq_path               = self.class.default_dlq_path
      @dispatcher_max_threads = DEFAULT_DISPATCHER_MAX_THREADS
      @dispatcher_max_queue   = DEFAULT_DISPATCHER_MAX_QUEUE
      @shutdown_timeout       = SmartMessage::DEFAULT_SHUTDOWN_TIMEOUT
      @built_logger           = nil
      self
    end

    def logger=(value)
      @logger       = value
      @built_logger = nil
    end

    LOG_SETTINGS.each do |name|
      define_method(:"#{name}=") do |value|
        instance_variable_set(:"@#{name}", value)
        @built_logger = nil
      end
    end

    # @param path [String, Pathname, nil] stored as an absolute path; nil or
    #   blank restores the default, as an empty $SMART_MESSAGE_DLQ_PATH does
    def dlq_path=(path)
      @dlq_path = path.to_s.strip.empty? ? self.class.default_dlq_path : File.expand_path(path.to_s)
    end

    # Was a logger configured?
    def logger_configured?
      !@logger.nil?
    end

    # Check if transport is configured
    def transport_configured?
      !@transport.nil?
    end

    # The logger every SmartMessage component uses unless a message class
    # sets its own.  Built once and reused.
    #
    # @return [#debug, #info, #warn, #error, #fatal]
    def default_logger
      @built_logger ||= build_logger
    end

    # The globally configured transport, or nil.
    def default_transport
      @transport
    end

    private

    def build_logger
      case @logger
      when nil
        SmartMessage::Logger::Null.new
      when :default
        SmartMessage::Logger::Lumberjack.new(**logger_options)
      when String, STDOUT, STDERR
        SmartMessage::Logger::Lumberjack.new(**logger_options.merge(log_file: @logger))
      else
        @logger
      end
    end

    # Build logger options from configuration
    def logger_options
      options = {}
      options[:level]           = @log_level  if @log_level
      options[:format]          = @log_format if @log_format
      options[:include_source]  = @log_include_source  unless @log_include_source.nil?
      options[:structured_data] = @log_structured_data unless @log_structured_data.nil?
      options[:colorize]        = @log_colorize        unless @log_colorize.nil?
      options.merge!(@log_options) if @log_options.is_a?(Hash)
      options
    end
  end
end
