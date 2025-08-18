# Logging in SmartMessage

SmartMessage provides flexible logging capabilities through its plugin architecture. This document covers the built-in default logger as well as how to create custom loggers.

## Table of Contents

- [Default Logger](#default-logger)
- [Configuration Options](#configuration-options)
- [Output Destinations](#output-destinations)
- [Log Levels](#log-levels)
- [Message Lifecycle Logging](#message-lifecycle-logging)
- [Rails Integration](#rails-integration)
- [Custom Loggers](#custom-loggers)
- [Examples](#examples)

## Default Logger

SmartMessage includes a built-in `SmartMessage::Logger::Default` class that automatically detects your environment and chooses the best logging approach:

- **Rails Applications**: Uses `Rails.logger` with tagged logging
- **Standalone Ruby**: Uses Ruby's standard `Logger` class with file output

### Quick Start

```ruby
class MyMessage < SmartMessage::Base
  property :content
  
  config do
    transport SmartMessage::Transport::StdoutTransport.new
    serializer SmartMessage::Serializer::JSON.new
    logger SmartMessage::Logger::Default.new  # Zero configuration!
  end
end
```

## Configuration Options

The default logger accepts several configuration options:

### Basic Configuration

```ruby
# Use defaults (Rails.logger or log/smart_message.log)
logger SmartMessage::Logger::Default.new

# Custom log file path
logger SmartMessage::Logger::Default.new(
  log_file: '/var/log/my_app/messages.log'
)

# Custom log level
logger SmartMessage::Logger::Default.new(
  level: Logger::DEBUG
)

# Both custom file and level
logger SmartMessage::Logger::Default.new(
  log_file: 'logs/custom.log',
  level: Logger::WARN
)
```

## Output Destinations

The default logger supports multiple output destinations:

### File Logging (Default)

```ruby
# Default file location (Rails convention)
logger SmartMessage::Logger::Default.new
# → log/smart_message.log

# Custom file path
logger SmartMessage::Logger::Default.new(
  log_file: '/var/log/application/messages.log'
)
```

**Features:**
- Automatic log rotation (10 files, 10MB each)
- Directory creation if needed
- Timestamped entries with clean formatting

### STDOUT Logging

Perfect for containerized applications (Docker, Kubernetes):

```ruby
logger SmartMessage::Logger::Default.new(
  log_file: STDOUT,
  level: Logger::INFO
)
```

### STDERR Logging

For error-focused logging:

```ruby
logger SmartMessage::Logger::Default.new(
  log_file: STDERR,
  level: Logger::WARN
)
```

### In-Memory Logging (Testing)

```ruby
require 'stringio'

logger SmartMessage::Logger::Default.new(
  log_file: StringIO.new,
  level: Logger::DEBUG
)
```

## Log Levels

The default logger supports all standard Ruby log levels:

| Level | Numeric Value | Description |
|-------|--------------|-------------|
| `Logger::DEBUG` | 0 | Detailed debugging information |
| `Logger::INFO` | 1 | General information messages |
| `Logger::WARN` | 2 | Warning messages |
| `Logger::ERROR` | 3 | Error messages |
| `Logger::FATAL` | 4 | Fatal error messages |

### Environment-Based Defaults

The default logger automatically sets appropriate log levels based on your environment:

- **Rails Production**: `Logger::INFO`
- **Rails Test**: `Logger::ERROR`
- **Rails Development**: `Logger::DEBUG`
- **Non-Rails**: `Logger::INFO`

## Message Lifecycle Logging

The default logger automatically logs key events in the message lifecycle:

### Message Creation

```ruby
# Logged at DEBUG level
message = MyMessage.new(content: "Hello")
# → [DEBUG] [SmartMessage] Created: MyMessage - {content: "Hello"}
```

### Message Publishing

```ruby
# Logged at INFO level
message.publish
# → [INFO] [SmartMessage] Published: MyMessage via StdoutTransport
```

### Message Reception

```ruby
# Logged at INFO level when message is received
# → [INFO] [SmartMessage] Received: MyMessage (45 bytes)
```

### Message Processing

```ruby
# Logged at INFO level after processing
# → [INFO] [SmartMessage] Processed: MyMessage - Success
```

### Subscription Management

```ruby
# Logged at INFO level
MyMessage.subscribe
# → [INFO] [SmartMessage] Subscribed: MyMessage

MyMessage.unsubscribe
# → [INFO] [SmartMessage] Unsubscribed: MyMessage
```

### Error Logging

```ruby
# Logged at ERROR level with full stack trace (DEBUG level)
# → [ERROR] [SmartMessage] Error in message processing: RuntimeError - Something went wrong
# → [DEBUG] [SmartMessage] Backtrace: ...
```

## Rails Integration

When running in a Rails application, the default logger provides enhanced integration:

### Automatic Detection

```ruby
# Automatically uses Rails.logger when available
logger SmartMessage::Logger::Default.new
```

### Tagged Logging

```ruby
# In Rails, all SmartMessage logs are tagged
Rails.logger.tagged('SmartMessage') do
  # All SmartMessage logging happens here
end
```

### Rails Log File Location

```ruby
# Uses Rails.root/log/smart_message.log when Rails is detected
logger SmartMessage::Logger::Default.new
# → Rails.root.join('log', 'smart_message.log')
```

### Rails Environment Handling

The logger respects Rails environment settings:

- **Production**: INFO level, structured logging
- **Development**: DEBUG level, verbose output  
- **Test**: ERROR level, minimal output

## Custom Loggers

You can create custom loggers by inheriting from `SmartMessage::Logger::Base`:

### Basic Custom Logger

```ruby
class SmartMessage::Logger::MyCustomLogger < SmartMessage::Logger::Base
  def initialize(external_logger)
    @logger = external_logger
  end
  
  def log_message_created(message)
    @logger.debug "Created message: #{message.class.name}"
  end
  
  def log_message_published(message, transport)
    @logger.info "Published #{message.class.name} via #{transport.class.name}"
  end
  
  # Implement other lifecycle methods as needed...
end
```

### Wrapper for Third-Party Loggers

```ruby
# Semantic Logger example
class SmartMessage::Logger::SemanticLogger < SmartMessage::Logger::Base
  def initialize(semantic_logger = nil)
    @logger = semantic_logger || SemanticLogger['SmartMessage']
  end
  
  def log_message_created(message)
    @logger.debug "Message created", message_class: message.class.name
  end
  
  def log_error(context, error)
    @logger.error "Error in #{context}", exception: error
  end
end
```

### Multi-Logger (Broadcast)

```ruby
class SmartMessage::Logger::MultiLogger < SmartMessage::Logger::Base
  def initialize(*loggers)
    @loggers = loggers
  end
  
  def log_message_created(message)
    @loggers.each { |logger| logger.log_message_created(message) }
  end
  
  # Other methods follow same pattern...
end

# Usage
logger SmartMessage::Logger::MultiLogger.new(
  SmartMessage::Logger::Default.new(log_file: 'app.log'),
  SmartMessage::Logger::Default.new(log_file: STDOUT),
  SmartMessage::Logger::MyCustomLogger.new(external_system)
)
```

## Examples

### Development Setup

```ruby
class OrderMessage < SmartMessage::Base
  property :order_id, String, required: true
  property :customer_id, String, required: true
  property :amount, Float, required: true
  
  config do
    transport SmartMessage::Transport::StdoutTransport.new(loopback: true)
    serializer SmartMessage::Serializer::JSON.new
    
    # Verbose logging for development
    logger SmartMessage::Logger::Default.new(
      log_file: STDOUT,
      level: Logger::DEBUG
    )
  end
  
  def self.process(message_header, message_payload)
    data = JSON.parse(message_payload)
    
    # Logger is available in process method
    logger.info "Processing order #{data['order_id']}"
    
    # Business logic here
    result = process_order(data)
    
    logger.info "Order #{data['order_id']} completed: #{result}"
    result
  end
end
```

### Production Setup

```ruby
class NotificationMessage < SmartMessage::Base
  property :recipient, String, required: true
  property :subject, String, required: true
  property :body, String, required: true
  
  config do
    transport SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::JSON.new
    
    # Production logging with file rotation
    logger SmartMessage::Logger::Default.new(
      log_file: '/var/log/app/notifications.log',
      level: Logger::INFO
    )
  end
end
```

### Docker/Kubernetes Setup

```ruby
class EventMessage < SmartMessage::Base
  property :event_type, String, required: true
  property :data, Hash, required: true
  
  config do
    transport SmartMessage::Transport::RedisTransport.new(
      redis_url: ENV['REDIS_URL']
    )
    serializer SmartMessage::Serializer::JSON.new
    
    # Container-friendly STDOUT logging
    logger SmartMessage::Logger::Default.new(
      log_file: STDOUT,
      level: ENV['LOG_LEVEL']&.upcase&.to_sym || Logger::INFO
    )
  end
end
```

### Testing Setup

```ruby
# In test_helper.rb or similar
class TestMessage < SmartMessage::Base
  property :test_data, Hash
  
  config do
    transport SmartMessage::Transport::MemoryTransport.new
    serializer SmartMessage::Serializer::JSON.new
    
    # Minimal logging for tests
    logger SmartMessage::Logger::Default.new(
      log_file: StringIO.new,
      level: Logger::FATAL  # Only fatal errors in tests
    )
  end
end
```

### Instance-Level Logger Override

```ruby
# Different logger for specific instances
class PriorityMessage < SmartMessage::Base
  property :priority, String
  property :data, Hash
  
  config do
    transport SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::JSON.new
    logger SmartMessage::Logger::Default.new  # Default logger
  end
end

# Override logger for high-priority messages
priority_logger = SmartMessage::Logger::Default.new(
  log_file: '/var/log/priority.log',
  level: Logger::DEBUG
)

urgent_message = PriorityMessage.new(priority: 'urgent', data: {...})
urgent_message.logger(priority_logger)  # Override for this instance
urgent_message.publish
```

## Best Practices

1. **Use the default logger** unless you have specific requirements
2. **Log to STDOUT** in containerized environments
3. **Use appropriate log levels** - avoid DEBUG in production
4. **Tag your logs** for better searchability
5. **Consider structured logging** for production systems
6. **Test your logging** - ensure logs are helpful for debugging
7. **Monitor log volume** - excessive logging can impact performance
8. **Rotate log files** to prevent disk space issues (default logger handles this)

## Troubleshooting

### No logs appearing
- Check log level settings
- Verify file permissions
- Ensure logger is configured

### Too much logging
- Increase log level (DEBUG → INFO → WARN → ERROR)
- Consider filtering in production

### Performance issues
- Lower log level in production
- Use asynchronous logging for high-volume systems
- Consider structured logging formats

### Rails integration not working
- Ensure Rails is loaded before SmartMessage
- Check that `Rails.logger` is available
- Verify Rails environment is set correctly

For more troubleshooting tips, see the [Troubleshooting Guide](troubleshooting.md).