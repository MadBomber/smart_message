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
    # This logger provides a simple Ruby Logger wrapper with enhanced formatting.
    # Applications can easily configure Rails.logger or other loggers through
    # the global configuration system instead.
    #
    # Usage:
    #   # Use default file logging
    #   SmartMessage.configure do |config|
    #     config.logger = SmartMessage::Logger::Default.new
    #   end
    #
    #   # Use custom options
    #   SmartMessage.configure do |config|
    #     config.logger = SmartMessage::Logger::Default.new(
    #       log_file: 'custom/path.log',
    #       level: Logger::DEBUG
    #     )
    #   end
    #
    #   # Log to STDOUT
    #   SmartMessage.configure do |config|
    #     config.logger = SmartMessage::Logger::Default.new(
    #       log_file: STDOUT,
    #       level: Logger::INFO
    #     )
    #   end
    #
    #   # Use Rails logger instead
    #   SmartMessage.configure do |config|
    #     config.logger = Rails.logger
    #   end
    class Default < Base
      attr_reader :logger, :log_file, :level

      def initialize(log_file: nil, level: nil)
        @log_file = log_file || 'log/smart_message.log'
        @level = level || ::Logger::INFO

        @logger = setup_logger
      end


      # General purpose logging methods matching Ruby's Logger interface
      # These methods capture caller information and embed it in the log message

      def debug(message = nil, &block)
        enhanced_log(:debug, message, caller_locations(1, 1).first, &block)
      end

      def info(message = nil, &block)
        enhanced_log(:info, message, caller_locations(1, 1).first, &block)
      end

      def warn(message = nil, &block)
        enhanced_log(:warn, message, caller_locations(1, 1).first, &block)
      end

      def error(message = nil, &block)
        enhanced_log(:error, message, caller_locations(1, 1).first, &block)
      end

      def fatal(message = nil, &block)
        enhanced_log(:fatal, message, caller_locations(1, 1).first, &block)
      end

      private

      # Enhanced logging method that embeds caller information
      def enhanced_log(level, message, caller_location, &block)
        if caller_location
          file_path = caller_location.path
          line_number = caller_location.lineno
          
          # If a block is provided, call it to get the message
          if block_given?
            actual_message = block.call
          else
            actual_message = message
          end
          
          # Embed caller info in the message
          enhanced_message = "[#{file_path}:#{line_number}] #{actual_message}"
          logger.send(level, enhanced_message)
        else
          # Fallback if caller information is not available
          if block_given?
            logger.send(level, &block)
          else
            logger.send(level, message)
          end
        end
      end

      def setup_logger
        # Handle IO objects (STDOUT, STDERR) vs file paths
        if @log_file.is_a?(IO) || @log_file.is_a?(StringIO)
          # For STDOUT/STDERR, don't use rotation
          ruby_logger = ::Logger.new(@log_file)
        else
          # For file paths, ensure directory exists and use rotation
          log_dir = File.dirname(@log_file)
          FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)

          ruby_logger = ::Logger.new(
            @log_file,
            10,           # Keep 10 old log files
            10_485_760    # Rotate when file reaches 10MB
          )
        end

        ruby_logger.level = @level

        # Set a formatter that includes file and line number
        ruby_logger.formatter = proc do |severity, datetime, progname, msg|
          timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')
          
          # Extract caller information if it's embedded in the message
          if msg.is_a?(String) && msg.match(/\A\[(.+?):(\d+)\] (.+)\z/)
            file_path = $1
            line_number = $2
            actual_msg = $3
            
            # Get just the filename from the full path
            filename = File.basename(file_path)
            
            "[#{timestamp}] #{severity.ljust(5)} -- #{filename}:#{line_number} : #{actual_msg}\n"
          else
            "[#{timestamp}] #{severity.ljust(5)} -- : #{msg}\n"
          end
        end

        ruby_logger
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

    end
  end
end
