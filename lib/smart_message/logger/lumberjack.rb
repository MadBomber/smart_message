# lib/smart_message/logger/lumberjack.rb
# encoding: utf-8
# frozen_string_literal: true

require 'lumberjack'
require 'fileutils'
require 'json'

module SmartMessage
  module Logger
    # Lumberjack-based logger implementation for SmartMessage
    #
    # Features:
    # - Source location (file:line) on every entry
    # - Keyword data on log calls (logger.info("text", order_id: 1))
    # - Text or JSON output
    # - Optional colour on the console
    # - Size-based or date-based rotation
    #
    # Usage:
    #   SmartMessage::Logger::Lumberjack.new(
    #     log_file: 'custom/smart_message.log',   # path, STDOUT, or STDERR
    #     level: :debug,
    #     format: :json,                          # :text or :json
    #     include_source: true,                   # Include source location
    #     structured_data: true,                  # Keep keyword data
    #     colorize: true,                         # Colour (console only)
    #     roll_by_size: true,                     # Size-based rolling ...
    #     max_file_size: 50 * 1024 * 1024,        # ... at 50 MB ...
    #     keep_files: 10                          # ... keeping 10 files
    #   )
    #
    # In JSON format each line has timestamp, level, message, and source;
    # keyword data is nested under "data" so it can never collide with them.
    class Lumberjack < Base
      DEFAULT_LOG_FILE = 'log/smart_message.log'

      # ANSI colour codes per level (text format, console output)
      COLORS = {
        debug: "\e[1;37;42m", # bold white on green
        info:  "\e[97m",      # bright white
        warn:  "\e[1;37;43m", # bold white on yellow
        error: "\e[1;37;41m", # bold white on red
        fatal: "\e[1;33;101m" # bold yellow on bright red
      }.freeze
      COLOR_RESET = "\e[0m"

      # Keyword data travels through Lumberjack inside this wrapper.
      # Lumberjack flattens a Hash attribute into dotted names
      # ("data.order_id"), which would change keys that contain a dot.
      LogData = Data.define(:fields)

      attr_reader :logger, :log_file, :format, :include_source, :structured_data, :colorize

      def initialize(log_file: nil, level: nil, format: :text, include_source: true, structured_data: true, colorize: false, **options)
        @log_file        = log_file || default_log_file
        @format          = format
        @include_source  = include_source
        @structured_data = structured_data
        @options         = options
        @colorize        = colorize && console_output?

        @logger = setup_lumberjack_logger(SmartMessage::Logger.severity(level || :info))
      end

      def level
        @logger.level
      end

      def level=(value)
        @logger.level = SmartMessage::Logger.severity(value)
      end

      def close
        @logger.close unless console_output?
      end

      # Check if output is going to console (STDOUT/STDERR)
      def console_output?
        @log_file == STDOUT || @log_file == STDERR
      end

      # Colour one line for a level.
      def self.colorize_line(line, level)
        color = COLORS[level.to_s.downcase.to_sym]
        color ? "#{color}#{line}#{COLOR_RESET}" : line
      end

      private

      def log(severity, message, data, &block)
        return nil if severity < level

        attributes = {}
        attributes[:data]   = LogData.new(fields: data) if @structured_data && !data.empty?
        attributes[:source] = caller_source if @include_source

        text = resolve_message(message, &block).to_s
        @logger.add_entry(severity, text, nil, attributes)
        nil
      end

      # file:line of the code that called the logger
      def caller_source
        location = caller_locations(3, 1)&.first
        location && "#{File.basename(location.path)}:#{location.lineno}"
      end

      def setup_lumberjack_logger(severity)
        ensure_log_directory

        # Console output gets an explicit Writer device so STDOUT/STDERR are
        # never treated as rotatable log files.  Files are opened by Lumberjack
        # itself, which passes the template and rotation settings to the device.
        device = console_output? ? ::Lumberjack::Device::Writer.new(@log_file, template: create_template) : @log_file

        ::Lumberjack::Logger.new(device, *rotation_args, level: severity, template: create_template, **rotation_options)
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

      # @return [Proc] turns a Lumberjack entry into one output line
      def create_template
        @format == :json ? json_template : text_template
      end

      def json_template
        lambda do |entry|
          attributes = entry.attributes || {}
          line = {
            timestamp: entry.time.strftime('%Y-%m-%d %H:%M:%S.%3N'),
            level:     entry.severity_label,
            message:   entry.message
          }
          line[:source] = attributes['source'] if attributes['source']
          line[:data]   = attributes['data'].fields if attributes['data']

          "#{JSON.generate(SmartMessage::Serializer::Json.jsonify(line))}\n"
        end
      end

      def text_template
        colorize = @colorize

        lambda do |entry|
          attributes = entry.attributes || {}
          timestamp  = entry.time.strftime('%Y-%m-%d %H:%M:%S.%3N')
          source     = attributes['source'] ? " #{attributes['source']}" : ''
          data       = attributes['data'] ? " #{attributes['data'].fields.inspect}" : ''

          line = "[#{timestamp}] #{entry.severity_label.ljust(5)} --#{source} : #{entry.message}#{data}"
          colorize ? Lumberjack.colorize_line(line, entry.severity_label) : line
        end
      end

      def default_log_file
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join('log', 'smart_message.log').to_s
        else
          DEFAULT_LOG_FILE
        end
      end
    end
  end
end
