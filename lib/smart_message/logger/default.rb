# lib/smart_message/logger/default.rb
# encoding: utf-8
# frozen_string_literal: true

require 'logger'
require 'fileutils'

module SmartMessage
  module Logger
    # A SmartMessage logger built on Ruby's standard Logger.
    #
    # Each line carries the file and line of the caller.
    #
    # Usage:
    #   SmartMessage.configure do |config|
    #     config.logger = SmartMessage::Logger::Default.new(
    #       log_file: 'log/smart_message.log',   # a path or an IO
    #       level: :debug
    #     )
    #   end
    class Default < Base
      DEFAULT_LOG_FILE = 'log/smart_message.log'

      attr_reader :logger, :log_file

      # @param log_file [String, IO, nil] path or IO; default log/smart_message.log
      # @param level [Symbol, String, Integer, nil] default :info
      def initialize(log_file: nil, level: nil)
        @log_file = log_file || DEFAULT_LOG_FILE
        @logger   = setup_logger
        self.level = level || :info
      end

      def level
        @logger.level
      end

      def level=(value)
        @logger.level = SmartMessage::Logger.severity(value)
      end

      def close
        @logger.close unless io_target?
      end

      private

      def log(severity, message, data, &block)
        return nil if severity < level

        location = caller_locations(2, 1)&.first
        source   = location ? "#{File.basename(location.path)}:#{location.lineno}" : nil
        text     = resolve_message(message, &block).to_s
        text     = "#{text} #{data.inspect}" unless data.empty?

        @logger.add(severity, text, source)
      end

      def io_target?
        @log_file.respond_to?(:write)
      end

      def setup_logger
        ruby_logger = if io_target?
                        ::Logger.new(@log_file)
                      else
                        FileUtils.mkdir_p(File.dirname(@log_file))
                        ::Logger.new(@log_file, 10, 10_485_760) # keep 10 files of 10 MB
                      end

        ruby_logger.formatter = proc do |severity, datetime, source, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')}] #{severity.ljust(5)} -- #{source} : #{msg}\n"
        end

        ruby_logger
      end
    end
  end
end
