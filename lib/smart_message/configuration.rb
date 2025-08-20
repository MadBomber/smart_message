# lib/smart_message/configuration.rb
# encoding: utf-8
# frozen_string_literal: true

module SmartMessage
  # Global configuration class for SmartMessage framework
  #
  # This class provides a centralized way for applications to configure
  # default behavior for all SmartMessage classes. Applications can set
  # global defaults for logger, transport, and serializer, which will be
  # used by all message classes unless explicitly overridden.
  #
  # IMPORTANT: No configuration = NO LOGGING
  # Applications must explicitly configure logging if they want it.
  #
  # Usage:
  #   # No configuration block = NO LOGGING (default behavior)
  #   
  #   # Use framework default logger (Lumberjack) with custom log file:
  #   SmartMessage.configure do |config|
  #     config.logger = "log/my_app.log"              # String path = Lumberjack logger
  #   end
  #   
  #   # Use framework default logger with STDOUT/STDERR:
  #   SmartMessage.configure do |config|
  #     config.logger = STDOUT                        # Log to STDOUT
  #     config.logger = STDERR                        # Log to STDERR
  #   end
  #   
  #   # Use framework default logger with default file (log/smart_message.log):
  #   SmartMessage.configure do |config|
  #     config.logger = :default                      # Framework default
  #   end
  #
  #   # Use custom logger:
  #   SmartMessage.configure do |config|
  #     config.logger = MyApp::Logger.new             # Custom logger object
  #     config.transport = MyApp::Transport.new
  #     config.serializer = MyApp::Serializer.new
  #   end
  #
  #   # Explicitly disable logging:
  #   SmartMessage.configure do |config|
  #     config.logger = nil                           # Explicit no logging
  #   end
  #
  #   # Individual message classes use these defaults automatically
  #   class OrderMessage < SmartMessage::Base
  #     property :order_id
  #     # No config block needed - uses global defaults
  #   end
  #
  #   # Override global defaults when needed
  #   class SpecialMessage < SmartMessage::Base
  #     config do
  #       logger MyApp::SpecialLogger.new  # Override just the logger
  #       # transport and serializer still use global defaults
  #     end
  #   end
  class Configuration
    attr_accessor :transport, :serializer
    attr_reader :logger
    
    def initialize
      @logger = nil
      @transport = nil
      @serializer = nil
      @logger_explicitly_set_to_nil = false
    end
    
    # Custom logger setter to track explicit nil assignment
    def logger=(value)
      @logger = value
      @logger_explicitly_set_to_nil = value.nil?
    end
    
    # Reset configuration to defaults
    def reset!
      @logger = nil
      @transport = nil
      @serializer = nil
      @logger_explicitly_set_to_nil = false
    end
    
    # Check if logger is configured (including explicit nil for no logging)
    def logger_configured?
      !@logger.nil? || @logger_explicitly_set_to_nil || @logger == :default || @logger.is_a?(String) || @logger == STDOUT || @logger == STDERR
    end
    
    # Check if transport is configured
    def transport_configured?
      !@transport.nil?
    end
    
    # Check if serializer is configured
    def serializer_configured?
      !@serializer.nil?
    end
    
    # Get the configured logger or no logging
    def default_logger
      case @logger
      when nil
        # If explicitly set to nil, use null logger (no logging)
        if @logger_explicitly_set_to_nil
          SmartMessage::Logger::Null.new
        else
          # Not configured, NO LOGGING
          SmartMessage::Logger::Null.new
        end
      when :default
        # Explicitly requested framework default
        framework_default_logger
      when String
        # String path means use Lumberjack logger with that file path
        SmartMessage::Logger::Lumberjack.new(log_file: @logger)
      when STDOUT, STDERR
        # STDOUT/STDERR constants mean use Lumberjack logger with that output
        SmartMessage::Logger::Lumberjack.new(log_file: @logger)
      else
        @logger
      end
    end
    
    # Get the configured transport or framework default
    def default_transport
      @transport || framework_default_transport
    end
    
    # Get the configured serializer or framework default
    def default_serializer
      @serializer || framework_default_serializer
    end
    
    private
    
    # Framework's built-in default logger (Lumberjack)
    def framework_default_logger
      SmartMessage::Logger::Lumberjack.new
    end
    
    # Framework's built-in default transport (Redis)
    def framework_default_transport
      SmartMessage::Transport::RedisTransport.new
    end
    
    # Framework's built-in default serializer (JSON)
    def framework_default_serializer
      SmartMessage::Serializer::Json.new
    rescue => e
      # Fallback if JSON serializer is not available
      nil
    end
  end
end