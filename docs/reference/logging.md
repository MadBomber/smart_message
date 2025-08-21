# Logging in SmartMessage

SmartMessage provides comprehensive logging capabilities with support for multiple output formats, colorization, structured logging, and file rolling. Built on the Lumberjack logging framework, it offers production-ready features with flexible configuration options.

## Table of Contents

- [Quick Start](#quick-start)
- [Configuration Options](#configuration-options)
- [Output Formats](#output-formats)
- [Colorized Console Output](#colorized-console-output)
- [File Rolling](#file-rolling)
- [Structured Logging](#structured-logging)
- [Application Integration](#application-integration)
- [SmartMessage Integration](#smartmessage-integration)
- [Examples](#examples)
- [Best Practices](#best-practices)

## Quick Start

Configure SmartMessage logging through the global configuration block:

```ruby
SmartMessage.configure do |config|
  config.logger = STDOUT              # Output destination
  config.log_level = :info           # Log level
  config.log_format = :text          # Format
  config.log_colorize = true         # Enable colors
end

# Access the logger in your application
logger = SmartMessage.configuration.default_logger
logger.info("Application started", component: "main")
```

## Configuration Options

### Global Configuration

All logging configuration is done through the `SmartMessage.configure` block:

```ruby
SmartMessage.configure do |config|
  # Required: Output destination
  config.logger = STDOUT                    # or file path, STDERR
  
  # Optional: Logging behavior
  config.log_level = :info                 # :debug, :info, :warn, :error, :fatal
  config.log_format = :text                # :text, :json
  config.log_colorize = true               # Enable colorized console output
  config.log_include_source = false        # Include file/line information
  config.log_structured_data = false       # Enable structured metadata
  
  # Optional: File rolling options
  config.log_options = {
    roll_by_size: true,
    max_file_size: 10 * 1024 * 1024,       # 10 MB
    keep_files: 5,                          # Keep 5 old files
    roll_by_date: false,                    # Alternative: date-based rolling
    date_pattern: '%Y-%m-%d'                # Daily pattern
  }
end
```

### Configuration Details

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `logger` | String/IO | Required | Output destination (file path, STDOUT, STDERR) |
| `log_level` | Symbol | `:info` | Log level (`:debug`, `:info`, `:warn`, `:error`, `:fatal`) |
| `log_format` | Symbol | `:text` | Output format (`:text`, `:json`) |
| `log_colorize` | Boolean | `false` | Enable colorized console output |
| `log_include_source` | Boolean | `false` | Include source file and line information |
| `log_structured_data` | Boolean | `false` | Enable structured data logging |
| `log_options` | Hash | `{}` | Additional Lumberjack options |

## Output Formats

### Text Format (Default)

Human-readable text output with optional colorization:

```ruby
SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_format = :text
  config.log_colorize = true
end

logger = SmartMessage.configuration.default_logger
logger.info("User login successful", user_id: 12345)
# Output: 2025-01-15 10:30:45 [INFO] User login successful user_id=12345
```

### JSON Format

Machine-readable structured JSON output:

```ruby
SmartMessage.configure do |config|
  config.logger = "log/application.log"
  config.log_format = :json
  config.log_structured_data = true
  config.log_include_source = true
end

logger = SmartMessage.configuration.default_logger
logger.info("User action", user_id: 12345, action: "login")
# Output: {"timestamp":"2025-01-15T10:30:45.123Z","level":"INFO","message":"User action","user_id":12345,"action":"login","source":"app.rb:42:in `authenticate`"}
```

## Colorized Console Output

SmartMessage provides colorized console output for improved readability during development:

```ruby
SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_format = :text
  config.log_colorize = true
end

logger = SmartMessage.configuration.default_logger
logger.debug("Debug message")    # Green background, black text, bold
logger.info("Info message")      # Bright white text
logger.warn("Warning message")   # Yellow background, white bold text
logger.error("Error message")    # Light red background, white bold text
logger.fatal("Fatal message")    # Light red background, yellow bold text
```

### Color Scheme

| Level | Foreground | Background | Style |
|-------|------------|------------|-------|
| DEBUG | Black | Green | Bold |
| INFO | Bright White | None | None |
| WARN | White | Yellow | Bold |
| ERROR | White | Light Red | Bold |
| FATAL | Yellow | Light Red | Bold |

**Note:** Colorization is automatically disabled for file output to keep log files clean.

## File Rolling

SmartMessage supports both size-based and date-based log file rolling:

### Size-Based Rolling

```ruby
SmartMessage.configure do |config|
  config.logger = "log/application.log"
  config.log_options = {
    roll_by_size: true,
    max_file_size: 10 * 1024 * 1024,  # 10 MB
    keep_files: 5                      # Keep 5 old files
  }
end
```

Files are named: `application.log`, `application.log.1`, `application.log.2`, etc.

### Date-Based Rolling

```ruby
SmartMessage.configure do |config|
  config.logger = "log/application.log"
  config.log_options = {
    roll_by_date: true,
    date_pattern: '%Y-%m-%d'  # Daily rolling
  }
end
```

Files are named: `application.log.2025-01-15`, `application.log.2025-01-14`, etc.

### Rolling Options

| Option | Type | Description |
|--------|------|-------------|
| `roll_by_size` | Boolean | Enable size-based rolling |
| `max_file_size` | Integer | Maximum file size in bytes |
| `keep_files` | Integer | Number of old files to keep |
| `roll_by_date` | Boolean | Enable date-based rolling |
| `date_pattern` | String | Date format pattern |

## Structured Logging

Enable structured data logging to include metadata with your log entries:

```ruby
SmartMessage.configure do |config|
  config.logger = "log/application.log"
  config.log_format = :json
  config.log_structured_data = true
  config.log_include_source = true
end

logger = SmartMessage.configuration.default_logger

# Log with structured data
logger.info("User registration", 
            user_id: "user123",
            email: "user@example.com",
            registration_source: "web",
            timestamp: Time.now.iso8601)

# Log with block for conditional data
logger.warn("Database slow query") do
  {
    query: "SELECT * FROM users WHERE status = ?",
    duration_ms: 1500,
    table: "users",
    slow_query: true
  }
end
```

## Application Integration

### Accessing the Logger

The configured logger is available globally:

```ruby
# Get the globally configured logger
logger = SmartMessage.configuration.default_logger

# Use in your application
logger.info("Application starting", version: "1.0.0")
logger.warn("Configuration missing", config_key: "database_url")
logger.error("Service unavailable", service: "payment_gateway")
```

### Class-Level Integration

```ruby
class OrderService
  def initialize
    @logger = SmartMessage.configuration.default_logger
  end
  
  def process_order(order)
    @logger.info("Processing order", 
                 order_id: order.id,
                 customer_id: order.customer_id,
                 amount: order.amount)
    
    begin
      # Process order logic
      result = perform_processing(order)
      
      @logger.info("Order completed", 
                   order_id: order.id,
                   status: "success",
                   processing_time_ms: result[:duration])
      
    rescue StandardError => e
      @logger.error("Order processing failed",
                    order_id: order.id,
                    error: e.message,
                    error_class: e.class.name)
      raise
    end
  end
end
```

## SmartMessage Integration

SmartMessage classes automatically use the configured logger:

```ruby
class OrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :customer_id, required: true
  property :amount, required: true
  
  config do
    transport SmartMessage::Transport::StdoutTransport.new
    serializer SmartMessage::Serializer::Json.new
    from 'order-service'
  end
  
  def process
    # Logger is automatically available
    logger.info("Processing order message",
                message_id: _sm_header.uuid,
                order_id: order_id,
                customer_id: customer_id,
                amount: amount)
    
    # Log the complete message structure
    logger.debug("Message details",
                 header: _sm_header.to_h,
                 payload: _sm_payload,
                 full_message: to_h)
    
    # Process the order
    case amount
    when 0..100
      logger.info("Small order processed", order_id: order_id)
    when 101..1000
      logger.warn("Medium order requires review", order_id: order_id)
    else
      logger.error("Large order requires manual approval", 
                   order_id: order_id, 
                   amount: amount)
    end
  end
end
```

## Examples

### Development Configuration

Perfect for local development with colorized console output:

```ruby
SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_level = :debug
  config.log_format = :text
  config.log_colorize = true
  config.log_include_source = true
end
```

### Production Configuration

Production setup with JSON logging and file rolling:

```ruby
SmartMessage.configure do |config|
  config.logger = "/var/log/app/smartmessage.log"
  config.log_level = :info
  config.log_format = :json
  config.log_colorize = false
  config.log_structured_data = true
  config.log_include_source = false
  config.log_options = {
    roll_by_size: true,
    max_file_size: 50 * 1024 * 1024,  # 50 MB
    keep_files: 10
  }
end
```

### Docker/Container Configuration

Container-friendly setup with structured STDOUT logging:

```ruby
SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_level = ENV['LOG_LEVEL']&.downcase&.to_sym || :info
  config.log_format = :json
  config.log_colorize = false
  config.log_structured_data = true
  config.log_include_source = true
end
```

### Testing Configuration

Minimal logging for test environments:

```ruby
SmartMessage.configure do |config|
  config.logger = STDERR
  config.log_level = :error
  config.log_format = :text
  config.log_colorize = false
end
```

### Multiple Logger Configurations

You can create multiple logger instances for different purposes:

```ruby
# Configure global logger
SmartMessage.configure do |config|
  config.logger = "log/application.log"
  config.log_level = :info
  config.log_format = :json
end

# Create additional loggers for specific needs
console_logger = SmartMessage::Logger::Lumberjack.new(
  log_file: STDERR,
  level: :warn,
  format: :text,
  colorize: true
)

debug_logger = SmartMessage::Logger::Lumberjack.new(
  log_file: "log/debug.log",
  level: :debug,
  format: :text,
  include_source: true
)

# Use in application
console_logger.warn("Service degraded")
debug_logger.debug("Detailed debugging info", state: app_state)
```

## Best Practices

### 1. Environment-Based Configuration

Configure logging based on your environment:

```ruby
case ENV['RAILS_ENV'] || ENV['ENVIRONMENT']
when 'production'
  SmartMessage.configure do |config|
    config.logger = "/var/log/app/smartmessage.log"
    config.log_level = :info
    config.log_format = :json
    config.log_structured_data = true
    config.log_options = { roll_by_size: true, max_file_size: 50.megabytes, keep_files: 10 }
  end
when 'development'
  SmartMessage.configure do |config|
    config.logger = STDOUT
    config.log_level = :debug
    config.log_format = :text
    config.log_colorize = true
    config.log_include_source = true
  end
when 'test'
  SmartMessage.configure do |config|
    config.logger = STDERR
    config.log_level = :error
    config.log_format = :text
  end
end
```

### 2. Structured Data

Use structured data for better log analysis:

```ruby
# Good: Structured data
logger.info("User action", 
            user_id: user.id, 
            action: "login", 
            ip_address: request.ip,
            user_agent: request.user_agent)

# Avoid: String interpolation
logger.info("User #{user.id} logged in from #{request.ip}")
```

### 3. Appropriate Log Levels

Use log levels appropriately:

- **DEBUG**: Detailed information for diagnosing problems
- **INFO**: General information about program execution
- **WARN**: Something unexpected happened, but the application is still working
- **ERROR**: A serious problem occurred, but the application can continue
- **FATAL**: A very serious error occurred, application may not be able to continue

### 4. Performance Considerations

- Use appropriate log levels in production (avoid DEBUG)
- Consider async logging for high-volume applications
- Use structured data instead of string concatenation
- Be mindful of log volume and storage costs

### 5. Security

- Never log sensitive data (passwords, tokens, credit card numbers)
- Sanitize user input before logging
- Use structured data to avoid log injection attacks

```ruby
# Good: Structured data prevents injection
logger.info("User input received", user_input: params[:query])

# Avoid: Direct string interpolation
logger.info("User searched for: #{params[:query]}")
```

### 6. Testing

Test your logging configuration:

```ruby
# Test that logs are being generated
require 'stringio'

log_output = StringIO.new
SmartMessage.configure do |config|
  config.logger = log_output
  config.log_level = :debug
end

logger = SmartMessage.configuration.default_logger
logger.info("Test message")

assert_includes log_output.string, "Test message"
```

For more information, see the comprehensive logging example at `examples/show_logger.rb`.