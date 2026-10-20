# lib/smart_message/logger/lumberjack.rb
# encoding: utf-8
# frozen_string_literal: true

require 'lumberjack'
require 'fileutils'
require 'json'
require 'colorize'

module SmartMessage
  module Logger
    # Lumberjack-based logger implementation for SmartMessage
    #
    # This logger uses the Lumberjack gem to provide enhanced structured logging
    # with automatic source location tracking, structured data support, and
    # better performance characteristics.
    #
    # Features:
    # - Automatic source location tracking (file:line) for every log entry
    # - Structured data logging for message headers and payloads
    # - Better performance than standard Ruby Logger
    # - JSON output support for machine-readable logs
    # - Customizable formatters and devices
    #
    # Usage:
    #   # Basic usage with file logging
    #   config do
    #     logger SmartMessage::Logger::Lumberjack.new
    #   end
    #
    #   # Custom configuration
    #   config do
    #     logger SmartMessage::Logger::Lumberjack.new(
    #       log_file: 'custom/smart_message.log',
    #       level: :debug,
    #       format: :json,                      # :text or :json
    #       include_source: true,               # Include source location
    #       structured_data: true,              # Log structured message data
    #       colorize: true,                     # Enable colorized output (console only)
    #       roll_by_date: true,                 # Enable date-based log rolling
    #       max_file_size: 50 * 1024 * 1024     # Max file size before rolling (50 MB)
    #     )
    #   end
    #
    #   # Log to STDOUT with colorized JSON format
    #   config do
    #     logger SmartMessage::Logger::Lumberjack.new(
    #       log_file: STDOUT,
    #       format: :json,
    #       colorize: true
    #     )
    #   end
    class Lumberjack < Base
      attr_reader :logger, :log_file, :level, :format, :include_source, :structured_data, :colorize

      def initialize(log_file: nil, level: nil, format: :text, include_source: true, structured_data: true, colorize: false, **options)
        @log_file = log_file || default_log_file
        @level = level || default_log_level
        @format = format
        @include_source = include_source
        @structured_data = structured_data
        @options = options
        
        # Set colorize after @log_file is set so console_output? works correctly
        @colorize = colorize && console_output?

        @logger = setup_lumberjack_logger
      end


      # General purpose logging methods matching Ruby's Logger interface
      # These methods capture caller information and add structured data

      def debug(message = nil, **structured_data, &block)
        return unless message || block_given?
        structured_data[:message] = message if message
        log_with_caller(:debug, 1, structured_data, &block)
      end

      def info(message = nil, **structured_data, &block)
        return unless message || block_given?
        structured_data[:message] = message if message
        log_with_caller(:info, 1, structured_data, &block)
      end

      def warn(message = nil, **structured_data, &block)
        return unless message || block_given?
        structured_data[:message] = message if message
        log_with_caller(:warn, 1, structured_data, &block)
      end

      def error(message = nil, **structured_data, &block)
        return unless message || block_given?
        structured_data[:message] = message if message
        log_with_caller(:error, 1, structured_data, &block)
      end

      def fatal(message = nil, **structured_data, &block)
        return unless message || block_given?
        structured_data[:message] = message if message
        log_with_caller(:fatal, 1, structured_data, &block)
      end

      # Check if output is going to console (STDOUT/STDERR)
      def console_output?
        @log_file == STDOUT || @log_file == STDERR
      end

      private

      def setup_lumberjack_logger
        ensure_log_directory

        # Console output gets an explicit Writer device so STDOUT/STDERR are
        # never treated as rotatable log files.  Files are opened by Lumberjack
        # itself, which passes the template and rotation settings to the device.
        device = console_output? ? ::Lumberjack::Device::Writer.new(@log_file, template: create_template) : @log_file

        ::Lumberjack::Logger.new(device, *rotation_args, level: normalize_level(@level), template: create_template, **rotation_options)
      end

      def ensure_log_directory
        return unless @log_file.is_a?(String) && !@log_file.start_with?('/dev/')

        FileUtils.mkdir_p(File.dirname(@log_file))
      end

      # Lumberjack 2.x uses the standard library Logger rotation arguments:
      #   size based: (keep_count, max_bytes)
      #   date based: ('daily' | 'weekly' | 'monthly')
      def rotation_args
        if @options[:roll_by_size]
          [@options[:keep_files] || 5, @options[:max_file_size] || (10 * 1024 * 1024)]
        elsif @options[:roll_by_date]
          [@options[:roll_period] || 'daily']
        else
          []
        end
      end

      # date_pattern names the rotated files (e.g. smart_message.log.2026-10-19)
      def rotation_options
        @options[:date_pattern] ? { shift_period_suffix: @options[:date_pattern] } : {}
      end

      def create_template
        # Line template shared by console and file devices (Lumberjack 2.x)
        colorize_enabled = @colorize
        include_source = @include_source
        
        case @format
        when :json
          # JSON template - return lambda that formats as JSON
          lambda do |entry|
            data = {
              timestamp: entry.time.strftime('%Y-%m-%d %H:%M:%S.%3N'),
              level: entry.severity_label,
              message: entry.message
            }

            # Add source location if available
            if include_source && entry['source']
              data[:source] = entry['source']
            end

            # Add any structured data
            (entry.attributes || {}).each do |key, value|
              next if key == 'source'
              data[key] = value
            end

            data.to_json + "\n"
          end
        else
          # Text template with optional colorization
          lambda do |entry|
            require 'colorize' if colorize_enabled
            
            timestamp = entry.time.strftime('%Y-%m-%d %H:%M:%S.%3N')
            level = entry.severity_label.ljust(5)
            source_info = include_source && entry['source'] ? " #{entry['source']}" : ""

            line = "[#{timestamp}] #{level} --#{source_info} : #{entry.message}"
            
            if colorize_enabled
              # Apply colorization with custom color scheme
              case entry.severity_label.downcase.to_sym
              when :debug
                # Debug: dark green background, white foreground, bold
                line.white.bold.on_green
              when :info
                # Info: bright white foreground (no background)
                line.light_white
              when :warn
                # Warn: yellow background, white foreground, bold
                line.white.bold.on_yellow
              when :error
                # Error: red background, white foreground, bold
                line.white.bold.on_red
              when :fatal
                # Fatal: bright red background, yellow foreground, bold
                line.yellow.bold.on_light_red
              else
                line
              end
            else
              line
            end
          end
        end
      end

      def log_with_caller(level, caller_depth, structured_data = {}, &block)
        return unless @logger.send("#{level}?")

        caller_info = get_caller_info(caller_depth + 1)
        tags = structured_data.dup
        text = tags.delete(:message)
        tags[:source] = caller_info if @include_source && caller_info

        message = block_given? ? block.call(caller_info) : (text || "")

        if tags.empty?
          @logger.send(level, message)
        else
          @logger.tag(tags) do
            @logger.send(level, message)
          end
        end
      end


      def get_caller_info(depth)
        return nil unless @include_source

        caller_location = caller_locations(depth + 1, 1).first
        return nil unless caller_location

        filename = File.basename(caller_location.path)
        line_number = caller_location.lineno
        "#{filename}:#{line_number}"
      end

      def normalize_level(level)
        case level
        when Symbol
          case level
          when :debug then ::Lumberjack::Severity::DEBUG
          when :info then ::Lumberjack::Severity::INFO
          when :warn then ::Lumberjack::Severity::WARN
          when :error then ::Lumberjack::Severity::ERROR
          when :fatal then ::Lumberjack::Severity::FATAL
          else ::Lumberjack::Severity::INFO
          end
        when Integer
          level
        else
          ::Lumberjack::Severity::INFO
        end
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
          when 'development', 'test'
            :info
          when 'production'
            :info
          else
            :info
          end
        else
          :info
        end
      end
      
    end
  end
end
