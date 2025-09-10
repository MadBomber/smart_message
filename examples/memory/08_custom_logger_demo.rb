#!/usr/bin/env ruby
# examples/06_custom_logger_example.rb
#
# Custom Logger Example: Comprehensive Message Logging
#
# This example demonstrates how to implement and use custom loggers in the SmartMessage
# framework. It shows different logging strategies including file logging, structured 
# logging, and audit trails for message processing workflows.
#
# IMPORTANT: Using the Default Logger or Custom Loggers
# ====================================================================
# SmartMessage now includes a DEFAULT LOGGER that automatically detects your environment:
# - Uses Rails.logger if running in a Rails application
# - Uses Ruby's standard Logger otherwise (logs to log/smart_message.log)
#
# To use the default logger (EASIEST OPTION):
#   config do
#     logger SmartMessage::Logger::Default.new
#   end
#
# To use the default logger with custom settings:
#   config do
#     logger SmartMessage::Logger::Default.new(
#       log_file: 'custom/path.log',
#       level: Logger::DEBUG
#     )
#   end
#
# To log to STDOUT (useful for Docker/Kubernetes):
#   config do
#     logger SmartMessage::Logger::Default.new(
#       log_file: STDOUT,
#       level: Logger::INFO
#     )
#   end
#
# To create your own custom logger:
#   1. Create a wrapper class that inherits from SmartMessage::Logger::Base
#   2. Store the Ruby logger instance in your wrapper
#   3. Implement the SmartMessage logging methods using your Ruby logger
#
# To use Rails.logger directly (without the default logger):
#   1. Create a wrapper that delegates to Rails.logger
#   2. Configure it at the class level: logger SmartMessage::Logger::RailsLogger.new
#   3. All messages will be logged to your Rails application logs

require_relative '../../lib/smart_message'
require 'logger'
require 'json'
require 'fileutils'

puts "=== SmartMessage Example: Custom Logger Implementation ==="
puts

# Custom File Logger Implementation
# This wrapper shows how to integrate Ruby's standard Logger class with SmartMessage.
# The same pattern works for Rails.logger, Semantic Logger, or any Ruby logger.
class SmartMessage::Logger::FileLogger < SmartMessage::Logger::Base
  attr_reader :log_file_path, :logger
  
  def initialize(log_file_path, level: Logger::INFO)
    @log_file_path = log_file_path
    
    # Ensure log directory exists
    log_dir = File.dirname(@log_file_path)
    FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
    
    # This is Ruby's standard Logger class from the 'logger' library
    # You could replace this with Rails.logger or any other logger:
    #   @logger = Rails.logger  # For Rails applications
    #   @logger = SemanticLogger['SmartMessage']  # For Semantic Logger
    #   @logger = $stdout.sync = Logger.new($stdout)  # For stdout logging
    @logger = Logger.new(@log_file_path)
    @logger.level = level
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')}] #{severity}: #{msg}\n"
    end
  end
  
  # Standard logging methods
  def debug(message = nil, &block)
    @logger.debug(message || block.call)
  end
  
  def info(message = nil, &block)
    @logger.info(message || block.call)
  end
  
  def warn(message = nil, &block)
    @logger.warn(message || block.call)
  end
  
  def error(message = nil, &block)
    @logger.error(message || block.call)
  end
  
  def fatal(message = nil, &block)
    @logger.fatal(message || block.call)
  end
end

# Structured JSON Logger Implementation
class SmartMessage::Logger::JSONLogger < SmartMessage::Logger::Base
  attr_reader :log_file_path
  
  def initialize(log_file_path)
    @log_file_path = log_file_path
    
    # Ensure log directory exists
    log_dir = File.dirname(@log_file_path)
    FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
  end
  
  # Standard logging methods with JSON output
  def debug(message = nil, &block)
    write_log_entry({
      level: 'DEBUG',
      message: message || block&.call,
      timestamp: Time.now.iso8601
    })
  end
  
  def info(message = nil, &block)
    write_log_entry({
      level: 'INFO',
      message: message || block&.call,
      timestamp: Time.now.iso8601
    })
  end
  
  def warn(message = nil, &block)
    write_log_entry({
      level: 'WARN',
      message: message || block&.call,
      timestamp: Time.now.iso8601
    })
  end
  
  def error(message = nil, &block)
    write_log_entry({
      level: 'ERROR',
      message: message || block&.call,
      timestamp: Time.now.iso8601
    })
  end
  
  def fatal(message = nil, &block)
    write_log_entry({
      level: 'FATAL',
      message: message || block&.call,
      timestamp: Time.now.iso8601
    })
  end
  
  private
  
  def write_log_entry(data)
    File.open(@log_file_path, 'a') do |file|
      file.puts(JSON.generate(data))
    end
  end
end

# Console Logger with Emoji Implementation
class SmartMessage::Logger::EmojiConsoleLogger < SmartMessage::Logger::Base
  def debug(message = nil, &block)
    puts "🐛 DEBUG: #{message || block&.call}"
  end
  
  def info(message = nil, &block)
    puts "ℹ️  INFO: #{message || block&.call}"
  end
  
  def warn(message = nil, &block)
    puts "⚠️  WARN: #{message || block&.call}"
  end
  
  def error(message = nil, &block)
    puts "❌ ERROR: #{message || block&.call}"
  end
  
  def fatal(message = nil, &block)
    puts "💀 FATAL: #{message || block&.call}"
  end
end

# Example: Simple Ruby Logger Wrapper
# This demonstrates the minimal wrapper needed for Ruby's standard Logger.
# Use this pattern when you want to integrate with existing logging infrastructure.
class SmartMessage::Logger::RubyLoggerWrapper < SmartMessage::Logger::Base
  def initialize(ruby_logger = nil)
    # Accept any Ruby logger instance, or create a default one
    @logger = ruby_logger || Logger.new(STDOUT)
  end
  
  # Standard logging methods that delegate to the Ruby logger
  def debug(message = nil, &block)
    @logger.debug(message, &block)
  end
  
  def info(message = nil, &block)
    @logger.info(message, &block)
  end
  
  def warn(message = nil, &block)
    @logger.warn(message, &block)
  end
  
  def error(message = nil, &block)
    @logger.error(message, &block)
  end
  
  def fatal(message = nil, &block)
    @logger.fatal(message, &block)
  end
end

# Example: Rails Logger Wrapper (for Rails applications)
# Uncomment and use this in your Rails application
# class SmartMessage::Logger::RailsLogger < SmartMessage::Logger::Base
#   def debug(message = nil, &block)
#     Rails.logger.tagged('SmartMessage') do
#       Rails.logger.debug(message || block&.call)
#     end
#   end
#   
#   def info(message = nil, &block)
#     Rails.logger.tagged('SmartMessage') do
#       Rails.logger.info(message || block&.call)
#     end
#   end
#   
#   def warn(message = nil, &block)
#     Rails.logger.tagged('SmartMessage') do
#       Rails.logger.warn(message || block&.call)
#     end
#   end
#   
#   def error(message = nil, &block)
#     Rails.logger.tagged('SmartMessage') do
#       Rails.logger.error(message || block&.call)
#     end
#   end
#   
#   def fatal(message = nil, &block)
#     Rails.logger.tagged('SmartMessage') do
#       Rails.logger.fatal(message || block&.call)
#     end
#   end
# end

# Multi-logger that broadcasts to multiple loggers
class SmartMessage::Logger::MultiLogger < SmartMessage::Logger::Base
  def initialize(*loggers)
    @loggers = loggers
  end
  
  def debug(message = nil, &block)
    @loggers.each { |logger| logger.debug(message, &block) }
  end
  
  def info(message = nil, &block)
    @loggers.each { |logger| logger.info(message, &block) }
  end
  
  def warn(message = nil, &block)
    @loggers.each { |logger| logger.warn(message, &block) }
  end
  
  def error(message = nil, &block)
    @loggers.each { |logger| logger.error(message, &block) }
  end
  
  def fatal(message = nil, &block)
    @loggers.each { |logger| logger.fatal(message, &block) }
  end
end

# Sample message class with comprehensive logging
class OrderProcessingMessage < SmartMessage::Base
  description "Order processing messages with comprehensive multi-logger configuration"
  
  property :order_id, 
    description: "Unique identifier for the customer order"
  property :customer_id, 
    description: "Identifier of the customer placing the order"
  property :amount, 
    description: "Total monetary amount of the order"
  property :status, 
    description: "Current processing status of the order"
  property :items, 
    description: "Array of items included in the order"
  
  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    
    # Configure multi-logger to demonstrate different logging approaches
    logger SmartMessage::Logger::MultiLogger.new(
      SmartMessage::Logger::EmojiConsoleLogger.new,
      SmartMessage::Logger::FileLogger.new('logs/order_processing.log', level: Logger::DEBUG),
      SmartMessage::Logger::JSONLogger.new('logs/order_processing.json')
    )
  end
  
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    # Simulate the logger being called during processing
    if logger
      logger.info { "[SmartMessage] Received: #{self.name} (#{message_payload.bytesize} bytes)" }
    end
    
    # Process the message
    order_data = JSON.parse(message_payload)
    result = "Order #{order_data['order_id']} processed successfully"
    
    puts "💼 OrderProcessing: #{result}"
    
    # Log processing completion
    if logger
      logger.info { "[SmartMessage] Processed: #{self.name} - #{result}" }
    end
    
    result
  end
  
  # Override publish to demonstrate logging hooks
  def publish
    # Log message creation
    logger_instance = self.class.logger || SmartMessage::Logger.default
    if logger_instance
      logger_instance.debug { "[SmartMessage] Created: #{self.class.name}" }
    end
    
    # Log publishing
    transport_instance = transport || self.class.transport
    if logger_instance
      logger_instance.info { "[SmartMessage] Published: #{self.class.name} via #{transport_instance.class.name.split('::').last}" }
    end
    
    # Call original publish method
    super
  rescue => error
    # Log any errors during publishing
    if logger_instance
      logger_instance.error { "[SmartMessage] Error: Failed to publish #{self.class.name} - #{error.class.name}: #{error.message}" }
    end
    raise
  end
end

# Notification message with different logger configuration
class NotificationMessage < SmartMessage::Base
  description "User notifications with file-based logging configuration"
  
  property :recipient, 
    description: "Target recipient for the notification"
  property :subject, 
    description: "Subject line or title of the notification"
  property :body, 
    description: "Main content body of the notification"
  property :priority, 
    description: "Priority level of the notification (low, normal, high, urgent)"
  
  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    
    # Use only file logger for notifications
    logger SmartMessage::Logger::FileLogger.new('logs/notifications.log', level: Logger::WARN)
  end
  
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    if logger
      logger.info { "[SmartMessage] Received: #{self.name} (#{message_payload.bytesize} bytes)" }
    end
    
    notification_data = JSON.parse(message_payload)
    result = "Notification sent to #{notification_data['recipient']}"
    
    puts "📬 Notification: #{result}"
    
    if logger
      logger.info { "[SmartMessage] Processed: #{self.name} - #{result}" }
    end
    
    result
  end
end

# Example: Message class using standard Ruby logger
# This demonstrates how to use Ruby's standard Logger in production code
class StandardLoggerMessage < SmartMessage::Base
  description "Demonstrates integration with standard Ruby Logger for production logging"
  
  property :content, 
    description: "Main content of the message to be logged"
  property :level, 
    description: "Logging level for the message (debug, info, warn, error)"
  
  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    
    # Example 1: Using Ruby's standard Logger directly
    # Create a standard Ruby logger that logs to STDOUT
    ruby_logger = Logger.new(STDOUT)
    ruby_logger.level = Logger::INFO
    ruby_logger.progname = 'SmartMessage'
    
    # Wrap it in our adapter
    logger SmartMessage::Logger::RubyLoggerWrapper.new(ruby_logger)
    
    # Example 2: Using a file-based Ruby logger (commented out)
    # file_logger = Logger.new('application.log', 'daily')  # Rotate daily
    # logger SmartMessage::Logger::RubyLoggerWrapper.new(file_logger)
    
    # Example 3: In Rails, you would use Rails.logger (commented out)
    # logger SmartMessage::Logger::RubyLoggerWrapper.new(Rails.logger)
  end
  
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    data = JSON.parse(message_payload)
    puts "📝 Processing: #{data['content']}"
    "Processed"
  end
end

# Example: Message using the built-in Default Logger
class DefaultLoggerMessage < SmartMessage::Base
  description "Demonstrates SmartMessage's built-in default logger with auto-detection"
  
  property :message, 
    description: "The message content to be logged using default logger"
  property :level, 
    description: "Log level (debug, info, warn, error, fatal)"
  
  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    
    # Use the built-in default logger - simplest option!
    logger SmartMessage::Logger::Default.new
  end
  
  def self.process(wrapper)
    message_header, message_payload = wrapper.split
    data = JSON.parse(message_payload)
    puts "🎯 DefaultLogger: Processing #{data['message']}"
    "Processed with default logger"
  end
end

# Service that uses instance-level logger override
class PriorityOrderService
  def initialize
    puts "🚀 PriorityOrderService: Starting with custom logger..."
    
    # Create a priority-specific logger
    @priority_logger = SmartMessage::Logger::FileLogger.new(
      'logs/priority_orders.log', 
      level: Logger::DEBUG
    )
  end
  
  def process_priority_order(order_data)
    # Use class-level logger override for this specific processing
    original_logger = OrderProcessingMessage.logger
    OrderProcessingMessage.logger(@priority_logger)
    
    begin
      message = OrderProcessingMessage.new(**order_data, from: 'PriorityOrderService')
      puts "⚡ Processing priority order with dedicated logger"
      message.publish
      message
    ensure
      # Restore original logger
      OrderProcessingMessage.logger(original_logger)
    end
  end
end

# Demo runner
class LoggerDemo
  def run
    puts "🚀 Starting Custom Logger Demo\n"
    
    # Clean up any existing log files for a fresh demo
    FileUtils.rm_rf('logs') if Dir.exist?('logs')
    
    # Subscribe to messages
    OrderProcessingMessage.subscribe
    NotificationMessage.subscribe
    
    puts "\n" + "="*70
    puts "Demonstrating Different Logger Configurations"
    puts "="*70
    
    # Demo 1: Using the built-in Default Logger (NEW!)
    puts "\n--- Demo 1: Using SmartMessage Default Logger ---"
    puts "The Default logger automatically uses Rails.logger or Ruby Logger"
    
    # Use the DefaultLoggerMessage class defined above
    DefaultLoggerMessage.subscribe
    default_msg = DefaultLoggerMessage.new(
      message: "Testing the built-in default logger",
      level: "info",
      from: 'LoggerDemo'
    )
    default_msg.publish
    sleep(0.5)
    
    # Demo 2: Standard order with multi-logger
    puts "\n--- Demo 2: Standard Order (Multi-Logger) ---"
    order1 = OrderProcessingMessage.new(
      order_id: "ORD-001",
      customer_id: "CUST-123",
      amount: 99.99,
      status: "pending",
      items: ["Widget A", "Widget B"],
      from: 'LoggerDemo'
    )
    order1.publish
    sleep(0.5)
    
    # Demo 3: Notification with file-only logger
    puts "\n--- Demo 3: Notification (File Logger Only) ---"
    notification = NotificationMessage.new(
      recipient: "customer@example.com",
      subject: "Order Confirmation",
      body: "Your order has been received",
      priority: "normal",
      from: 'LoggerDemo'
    )
    notification.publish
    sleep(0.5)
    
    # Demo 4: Priority order with instance-level logger override
    puts "\n--- Demo 4: Priority Order (Instance Logger Override) ---"
    priority_service = PriorityOrderService.new
    priority_order = priority_service.process_priority_order(
      order_id: "ORD-PRIORITY-001",
      customer_id: "VIP-456",
      amount: 299.99,
      status: "urgent",
      items: ["Premium Widget", "Express Shipping"],
      from: 'PriorityOrderService'
    )
    sleep(0.5)
    
    # Demo 5: Using standard Ruby logger
    puts "\n--- Demo 5: Using Standard Ruby Logger ---"
    
    # Use the StandardLoggerMessage class that demonstrates Ruby's standard logger
    StandardLoggerMessage.subscribe
    
    # Create and send a message - watch for the Ruby logger output
    msg = StandardLoggerMessage.new(
      content: "Testing with Ruby's standard logger",
      level: "info",
      from: 'LoggerDemo'
    )
    
    # The logger will output to STDOUT using Ruby's standard format
    msg.publish
    sleep(0.5)
    
    puts "\nNote: The above used Ruby's standard Logger class wrapped for SmartMessage"
    puts "You can use ANY Ruby logger this way: Logger.new, Rails.logger, etc."
    
    # Demo 6: Error handling with logging
    puts "\n--- Demo 6: Error Handling with Logging ---"
    begin
      # Create a message that will cause an error
      faulty_order = OrderProcessingMessage.new(
        order_id: nil,  # This might cause issues
        customer_id: "ERROR-TEST",
        amount: "invalid_amount",
        status: "error_demo",
        from: 'LoggerDemo'
      )
      
      # Simulate an error during processing
      if OrderProcessingMessage.logger
        error = StandardError.new("Invalid order data provided")
        OrderProcessingMessage.logger.error { "[SmartMessage] Error: Simulated error for demo - #{error.class.name}: #{error.message}" }
      end
      
    rescue => error
      puts "🔍 Caught demonstration error: #{error.message}"
    end
    
    # Show log file contents
    puts "\n" + "="*70
    puts "📋 Log File Contents"
    puts "="*70
    
    show_log_contents
    
    puts "\n✨ Demo completed!"
    puts "\nThis example demonstrated:"
    puts "• SmartMessage::Logger::Default - Built-in logger that auto-detects Rails/Ruby"
    puts "• Integration with Ruby's standard Logger class"
    puts "• How to wrap Rails.logger or any Ruby logger for SmartMessage"
    puts "• Custom logger implementations (File, JSON, Console, Multi-logger)"
    puts "• Class-level and instance-level logger configuration"
    puts "• Different logging strategies for different message types"
    puts "• Error logging and message lifecycle logging"
    puts "• Log file management and structured logging formats"
    puts "\nKEY TAKEAWAY: Use SmartMessage::Logger::Default.new for instant logging!"
    puts "It automatically uses Rails.logger in Rails or creates a Ruby Logger otherwise."
  end
  
  private
  
  def show_log_contents
    log_files = Dir.glob('logs/*.log') + Dir.glob('logs/*.json')
    
    log_files.each do |log_file|
      next unless File.exist?(log_file)
      
      puts "\n📁 #{log_file}:"
      puts "-" * 50
      
      content = File.read(log_file)
      if content.length > 500
        puts content[0..500] + "\n... (truncated, #{content.length} total characters)"
      else
        puts content
      end
    end
    
    if log_files.empty?
      puts "⚠️  No log files found (they may not have been created yet)"
    end
  end
end

# Run the demo if this file is executed directly
if __FILE__ == $0
  demo = LoggerDemo.new
  demo.run
end