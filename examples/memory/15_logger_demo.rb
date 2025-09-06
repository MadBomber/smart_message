#!/usr/bin/env ruby
# examples/show_logger.rb
#
# Demonstrates the various features of the SmartMessage default logger
# and shows how applications can use the logger directly.

require_relative '../lib/smart_message'

puts "=" * 80
puts "SmartMessage Logger Feature Demonstration"
puts "=" * 80

# Example 1: Basic Logger Configuration
puts "\n1. Basic Logger Configuration"
puts "-" * 40

SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_level = :info
  config.log_format = :text
  config.log_colorize = true
end

# Get the configured logger for direct use
logger = SmartMessage.configuration.default_logger
puts "✓ Logger type: #{logger.class}"
puts "✓ Log level: #{logger.level}"
puts "✓ Format: #{logger.format}"
puts "✓ Colorized: #{logger.colorize}"

# Demonstrate different log levels with colors
puts "\nTesting different log levels (should show colors):"
logger.debug("This is a debug message - appears in light gray")
logger.info("This is an info message - appears in white")
logger.warn("This is a warning message - appears in yellow")
logger.error("This is an error message - appears in red")
logger.fatal("This is a fatal message - appears in bold red")

# Example 2: JSON Format Logger
puts "\n\n2. JSON Format Logger"
puts "-" * 40

SmartMessage.reset_configuration!
SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_level = :info
  config.log_format = :json
  config.log_include_source = true
  config.log_structured_data = true
  config.log_colorize = false  # No colors in JSON
end

json_logger = SmartMessage.configuration.default_logger
puts "✓ JSON Logger configured"

json_logger.info("JSON formatted message")
json_logger.warn("Warning with structured data",
                 component: "auth",
                 user_id: 12345,
                 action: "login_attempt")
json_logger.error("Error with context",
                  error_code: "AUTH_001",
                  timestamp: Time.now.iso8601,
                  severity: "high")

# Example 3: File Logger with Rolling
puts "\n\n3. File Logger with Size-based Rolling"
puts "-" * 40

SmartMessage.reset_configuration!
SmartMessage.configure do |config|
  config.logger = "log/demo_app.log"
  config.log_level = :debug
  config.log_format = :text
  config.log_include_source = true
  config.log_colorize = false  # No colors for file output
  config.log_options = {
    roll_by_size: true,
    max_file_size: 1024,  # Small size for demo (1KB)
    keep_files: 3
  }
end

file_logger = SmartMessage.configuration.default_logger
puts "✓ File logger with rolling configured"
puts "✓ Log file: #{file_logger.log_file}"
puts "✓ Rolling enabled: #{file_logger.respond_to?(:options) ? 'Yes' : 'No'}"

# Generate some log entries to trigger rolling
puts "\nGenerating log entries (check log/ directory)..."
50.times do |i|
  file_logger.info("Log entry #{i + 1} - generating content to trigger file rolling when size limit is reached")
  file_logger.debug("Debug entry #{i + 1}", entry_number: i + 1, batch: "demo")
end

puts "✓ Generated 100 log entries to demonstrate file rolling"

# Example 4: Date-based Rolling Logger
puts "\n\n4. Date-based Rolling Logger"
puts "-" * 40

SmartMessage.reset_configuration!
SmartMessage.configure do |config|
  config.logger = "log/daily_app.log"
  config.log_level = :info
  config.log_format = :text
  config.log_options = {
    roll_by_date: true,
    date_pattern: '%Y-%m-%d'
  }
end

date_logger = SmartMessage.configuration.default_logger
puts "✓ Date-based rolling logger configured"

date_logger.info("Application started", app_version: "1.2.3")
date_logger.info("Daily log rotation enabled")

# Example 5: Application Logger Pattern
puts "\n\n5. Application Logger Pattern"
puts "-" * 40

# Configure a production-like logger
SmartMessage.reset_configuration!
SmartMessage.configure do |config|
  config.logger = "log/application.log"
  config.log_level = :info
  config.log_format = :json
  config.log_include_source = true
  config.log_structured_data = true
  config.log_options = {
    roll_by_size: true,
    max_file_size: 10 * 1024 * 1024,  # 10 MB
    keep_files: 5,
    roll_by_date: false
  }
end

# Create an application class that uses the SmartMessage logger
class DemoApplication
  def initialize
    @logger = SmartMessage.configuration.default_logger
    @logger.info("DemoApplication initialized", component: "app", pid: Process.pid)
  end

  def start
    @logger.info("Starting application", action: "start")

    # Simulate some application work
    process_users
    handle_requests

    @logger.info("Application started successfully", action: "start", status: "success")
  end

  def stop
    @logger.info("Stopping application", action: "stop")
    @logger.info("Application stopped", action: "stop", status: "success")
  end

  private

  def process_users
    @logger.debug("Processing user data", action: "process_users")

    users = [
      { id: 1, name: "Alice", email: "alice@example.com" },
      { id: 2, name: "Bob", email: "bob@example.com" },
      { id: 3, name: "Charlie", email: "charlie@example.com" }
    ]

    users.each do |user|
      @logger.info("Processing user",
                   action: "process_user",
                   user_id: user[:id],
                   user_name: user[:name])

      # Simulate some processing time
      sleep(0.1)
    end

    @logger.info("User processing completed",
                 action: "process_users",
                 status: "completed",
                 user_count: users.size)
  end

  def handle_requests
    @logger.debug("Handling incoming requests", action: "handle_requests")

    requests = [
      { method: "GET", path: "/api/users", status: 200 },
      { method: "POST", path: "/api/users", status: 201 },
      { method: "GET", path: "/api/users/1", status: 200 },
      { method: "DELETE", path: "/api/users/2", status: 404 }
    ]

    requests.each_with_index do |request, index|
      level = request[:status] >= 400 ? :warn : :info

      @logger.send(level, "HTTP request processed",
                   action: "http_request",
                   method: request[:method],
                   path: request[:path],
                   status_code: request[:status],
                   request_id: "req_#{index + 1}")
    end

    @logger.info("Request handling completed",
                 action: "handle_requests",
                 status: "completed",
                 request_count: requests.size)
  end
end

puts "✓ Application logger configured for production use"

# Run the demo application
app = DemoApplication.new
app.start
sleep(0.5)  # Simulate runtime
app.stop

# Example 6: Multiple Logger Configurations
puts "\n\n6. Multiple Logger Configurations"
puts "-" * 40

# You can create multiple logger instances with different configurations
console_logger = SmartMessage::Logger::Lumberjack.new(
  log_file: STDERR,
  level: :warn,
  format: :text,
  colorize: true,
  include_source: false
)

file_logger_json = SmartMessage::Logger::Lumberjack.new(
  log_file: "log/json_output.log",
  level: :debug,
  format: :json,
  include_source: true,
  structured_data: true
)

puts "✓ Console logger (STDERR, warnings only, colorized)"
puts "✓ File logger (JSON format, debug level)"

console_logger.warn("This appears on console in yellow")
console_logger.error("This appears on console in red")
console_logger.info("This won't appear (below warn level)")

file_logger_json.debug("Debug message to JSON file", module: "demo", test: true)
file_logger_json.info("Info message to JSON file", event: "demonstration")

# Example 7: Integration with SmartMessage Classes
puts "\n\n7. Integration with SmartMessage Classes"
puts "-" * 40

# Reset to a simple configuration for message examples
SmartMessage.reset_configuration!
SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_level = :debug
  config.log_format = :text
  config.log_colorize = true
end

# Define a sample message class
class DemoMessage < SmartMessage::Base
  property :title, required: true
  property :content
  property :priority, default: 'normal'

  config do
    transport SmartMessage::Transport::StdoutTransport.new
    serializer SmartMessage::Serializer::Json.new
    from 'demo-logger-app'
  end

  def process
    # Messages automatically use the configured SmartMessage logger
    logger.info("Processing demo message",
                message_id: _sm_header.uuid,
                title: title,
                priority: priority)

    case priority
    when 'high'
      logger.warn("High priority message requires attention",
                  title: title,
                  priority: priority)
    when 'critical'
      logger.error("Critical message needs immediate action",
                   title: title,
                   priority: priority)
    else
      logger.info("Normal message processed",
                  title: title,
                  priority: priority)
    end
  end
end

puts "✓ SmartMessage classes automatically use the configured logger"

# Create and publish some demo messages
messages = [
  { title: "Welcome Message", content: "Hello, World!", priority: "normal" },
  { title: "System Alert", content: "High CPU usage detected", priority: "high" },
  { title: "Security Breach", content: "Unauthorized access attempt", priority: "critical" }
]

# Get the logger for demonstrating message instance logging
app_logger = SmartMessage.configuration.default_logger

messages.each do |msg_data|
  begin
    message = DemoMessage.new(
      title: msg_data[:title],
      content: msg_data[:content],
      priority: msg_data[:priority]
    )

    puts "<<<>>>>>>>>"
    # Example of logging an info message that contains the message instance
    # Shows how to log SmartMessage structure: full message, header, and payload
    app_logger.info({action: "Publishing SmartMessage instance",
                    message_class: message.class.name,
                    message_uuid: message._sm_header.uuid,
                    message_from: message._sm_header.from,
                    header: message._sm_header,
                    payload: message._sm_payload,
                    full_message: message})

    puts "<<<<<<<<<<"

    message.publish
    sleep(0.2)  # Small delay for demonstration
  rescue => e
    puts "Error creating/publishing message: #{e.message}"
  end
end

puts "\n" + "=" * 80
puts "Logger Demonstration Complete!"
puts "=" * 80

puts "\nFiles created in log/ directory:"
log_files = Dir.glob("log/**/*").select { |f| File.file?(f) }
log_files.each do |file|
  size = File.size(file)
  puts "  #{file} (#{size} bytes)"
end

puts "\nFeatures demonstrated:"
puts "  ✓ Basic text logging with colors"
puts "  ✓ JSON structured logging"
puts "  ✓ File logging with size-based rolling"
puts "  ✓ Date-based log rolling"
puts "  ✓ Application integration patterns"
puts "  ✓ Multiple logger configurations"
puts "  ✓ SmartMessage class integration"
puts "  ✓ Different log levels and formatting"
puts "  ✓ Structured data logging"
puts "  ✓ Source location tracking"

puts "\nTip: Check the generated log files to see the different output formats!"
