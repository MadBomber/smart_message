# lib/smart_message/logger/default.rb
# encoding: utf-8
# frozen_string_literal: true

require 'logger'
require 'fileutils'
require 'stringio'

module SmartMessage
  module Logger
    # Default logger implementation for SmartMessage
    # 
    # This logger automatically detects and uses the best available logging option:
    # - Rails.logger if running in a Rails application
    # - Standard Ruby Logger writing to log/smart_message.log otherwise
    #
    # Usage:
    #   # In your message class
    #   config do
    #     logger SmartMessage::Logger::Default.new
    #   end
    #
    #   # Or with custom options
    #   config do
    #     logger SmartMessage::Logger::Default.new(
    #       log_file: 'custom/path.log',    # File path
    #       level: Logger::DEBUG
    #     )
    #   end
    #
    #   # To log to STDOUT instead of a file
    #   config do
    #     logger SmartMessage::Logger::Default.new(
    #       log_file: STDOUT,               # STDOUT or STDERR
    #       level: Logger::INFO
    #     )
    #   end
    class Default < Base
      attr_reader :logger, :log_file, :level
      
      def initialize(log_file: nil, level: nil)
        @log_file = log_file || default_log_file
        @level = level || default_log_level
        
        @logger = setup_logger
      end
      
      # Message lifecycle logging methods
      
      def log_message_created(message)
        logger.debug { "[SmartMessage] Created: #{message.class.name} - #{message_summary(message)}" }
      end
      
      def log_message_published(message, transport)
        logger.info { "[SmartMessage] Published: #{message.class.name} via #{transport.class.name.split('::').last}" }
      end
      
      def log_message_received(message_class, payload)
        logger.info { "[SmartMessage] Received: #{message_class.name} (#{payload.bytesize} bytes)" }
      end
      
      def log_message_processed(message_class, result)
        logger.info { "[SmartMessage] Processed: #{message_class.name} - #{truncate(result.to_s, 100)}" }
      end
      
      def log_message_subscribe(message_class, handler = nil)
        handler_desc = handler ? " with handler: #{handler}" : ""
        logger.info { "[SmartMessage] Subscribed: #{message_class.name}#{handler_desc}" }
      end
      
      def log_message_unsubscribe(message_class)
        logger.info { "[SmartMessage] Unsubscribed: #{message_class.name}" }
      end
      
      # Error logging
      
      def log_error(context, error)
        logger.error { "[SmartMessage] Error in #{context}: #{error.class.name} - #{error.message}" }
        logger.debug { "[SmartMessage] Backtrace:\n#{error.backtrace.join("\n")}" } if error.backtrace
      end
      
      def log_warning(message)
        logger.warn { "[SmartMessage] Warning: #{message}" }
      end
      
      # General purpose logging methods matching Ruby's Logger interface
      
      def debug(message = nil, &block)
        logger.debug(message, &block)
      end
      
      def info(message = nil, &block)
        logger.info(message, &block)
      end
      
      def warn(message = nil, &block)
        logger.warn(message, &block)
      end
      
      def error(message = nil, &block)
        logger.error(message, &block)
      end
      
      def fatal(message = nil, &block)
        logger.fatal(message, &block)
      end
      
      private
      
      def setup_logger
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          # Use Rails logger if available
          setup_rails_logger
        else
          # Use standard Ruby logger
          setup_ruby_logger
        end
      end
      
      def setup_rails_logger
        # Wrap Rails.logger to ensure our messages are properly tagged
        RailsLoggerWrapper.new(Rails.logger, level: @level)
      end
      
      def setup_ruby_logger
        # Handle IO objects (STDOUT, STDERR) vs file paths
        if @log_file.is_a?(IO) || @log_file.is_a?(StringIO)
          # For STDOUT/STDERR, don't use rotation
          ruby_logger = ::Logger.new(@log_file)
        else
          # For file paths, ensure directory exists and use rotation
          FileUtils.mkdir_p(File.dirname(@log_file))
          
          ruby_logger = ::Logger.new(
            @log_file,
            10,           # Keep 10 old log files
            10_485_760    # Rotate when file reaches 10MB
          )
        end
        
        ruby_logger.level = @level
        
        # Set a clean formatter
        ruby_logger.formatter = proc do |severity, datetime, progname, msg|
          timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')
          "[#{timestamp}] #{severity.ljust(5)} -- : #{msg}\n"
        end
        
        ruby_logger
      end
      
      def default_log_file
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join('log', 'smart_message.log').to_s
        else
          'log/smart_message.log'
        end
      end
      
      def default_log_level
        if defined?(Rails) && Rails.respond_to?(:env)
          case Rails.env
          when 'production'
            ::Logger::INFO
          when 'test'
            ::Logger::ERROR
          else
            ::Logger::DEBUG
          end
        else
          # Default to INFO for non-Rails environments
          ::Logger::INFO
        end
      end
      
      def message_summary(message)
        # Create a brief summary of the message for logging
        if message.respond_to?(:to_h)
          data = message.to_h
          # Remove internal header for cleaner logs
          data.delete(:_sm_header)
          data.delete('_sm_header')
          truncate(data.inspect, 200)
        else
          truncate(message.inspect, 200)
        end
      end
      
      def truncate(string, max_length)
        return string if string.length <= max_length
        "#{string[0...max_length]}..."
      end
      
      # Internal wrapper for Rails.logger to handle tagged logging
      class RailsLoggerWrapper
        def initialize(rails_logger, level: nil)
          @rails_logger = rails_logger
          @rails_logger.level = level if level
        end
        
        def method_missing(method, *args, &block)
          if @rails_logger.respond_to?(:tagged)
            @rails_logger.tagged('SmartMessage') do
              @rails_logger.send(method, *args, &block)
            end
          else
            @rails_logger.send(method, *args, &block)
          end
        end
        
        def respond_to_missing?(method, include_private = false)
          @rails_logger.respond_to?(method, include_private)
        end
      end
    end
  end
end