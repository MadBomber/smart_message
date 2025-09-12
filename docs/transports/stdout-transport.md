# STDOUT Transport

The **STDOUT Transport** is a development and debugging transport that outputs messages to the console or files in human-readable formats. It inherits from `FileTransport` and provides specialized output formatting capabilities.

## Overview

STDOUT Transport is perfect for:
- **Development debugging** - See messages in real-time during development
- **Application logging** - Structured message logging to files or console
- **Message tracing** - Track message flow through systems
- **Integration testing** - Verify message content and flow
- **Format testing** - Demonstrate different message serialization formats

## Key Features

- 📄 **Multiple Output Formats** - Pretty, JSON Lines, and compact JSON
- 🖥️ **Console or File Output** - Direct to STDOUT or file paths
- 🔄 **Optional Loopback** - Process messages locally after output
- 🧵 **Thread-Safe** - Safe for concurrent message publishing
- 🛠️ **No Dependencies** - Built-in Ruby formatting capabilities
- 🎨 **Pretty Printing** - Human-readable format using amazing_print

## Architecture

```
Publisher → StdoutTransport → Console/File Output → Optional Loopback → Local Processing
         (format selection)   (thread-safe)      (if enabled)      (message handling)
```

STDOUT Transport inherits from `FileTransport` and adds specialized console output capabilities with multiple formatting options.

## Configuration

### Basic Setup

```ruby
# Minimal configuration (outputs to console)
transport = SmartMessage::Transport::StdoutTransport.new

# With file output
transport = SmartMessage::Transport::StdoutTransport.new(
  file_path: '/var/log/messages.log'
)

# With format specification
transport = SmartMessage::Transport::StdoutTransport.new(
  format: :pretty,
  loopback: true
)

# Full configuration
transport = SmartMessage::Transport::StdoutTransport.new(
  file_path: '/var/log/app.log',
  format: :jsonl,
  loopback: false,
  auto_create_dirs: true
)
```

### Using with SmartMessage

```ruby
# Configure as default transport
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::StdoutTransport.new(
    format: :pretty
  )
end

# Use in message class
class LogMessage < SmartMessage::Base
  property :level, required: true
  property :message, required: true
  property :timestamp, default: -> { Time.now.iso8601 }
  
  transport :stdout
  
  def process
    puts "Log entry processed: #{level} - #{message}"
  end
end
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `format` | Symbol | `:pretty` | Output format (`:pretty`, `:jsonl`, `:json`) |
| `file_path` | String | `nil` | File path for output (nil = STDOUT) |
| `loopback` | Boolean | `false` | Process messages locally after output |
| `auto_create_dirs` | Boolean | `true` | Automatically create parent directories |

## Output Formats

### Pretty Format (`:pretty`)

Uses `amazing_print` for human-readable, colorized output:

```ruby
transport = SmartMessage::Transport::StdoutTransport.new(format: :pretty)

class UserMessage < SmartMessage::Base
  property :name
  property :email
  transport transport
end

UserMessage.new(name: "Alice Johnson", email: "alice@example.com").publish

# Output:
# {
#     :name => "Alice Johnson",
#     :email => "alice@example.com"
# }
```

### JSON Lines Format (`:jsonl`)

One JSON object per line, ideal for log processing:

```ruby
transport = SmartMessage::Transport::StdoutTransport.new(format: :jsonl)

UserMessage.new(name: "Bob Smith", email: "bob@example.com").publish
UserMessage.new(name: "Carol Williams", email: "carol@example.com").publish

# Output:
# {"name":"Bob Smith","email":"bob@example.com"}
# {"name":"Carol Williams","email":"carol@example.com"}
```

### Compact JSON Format (`:json`)

Compact JSON with no newlines:

```ruby
transport = SmartMessage::Transport::StdoutTransport.new(format: :json)

UserMessage.new(name: "David Brown", email: "david@example.com").publish

# Output:
# {"name":"David Brown","email":"david@example.com"}
```

## Usage Examples

### Development Debugging

```ruby
class DebugMessage < SmartMessage::Base
  property :component, required: true
  property :action, required: true
  property :data
  property :timestamp, default: -> { Time.now }
  
  transport SmartMessage::Transport::StdoutTransport.new(
    format: :pretty,
    loopback: true
  )
  
  def process
    puts "[DEBUG] #{component}.#{action} completed at #{timestamp}"
  end
end

# Publishing shows both formatted output and processes locally
DebugMessage.new(
  component: "UserService",
  action: "create_user",
  data: { user_id: 123, email: "user@example.com" }
).publish

# Output (formatted):
# {
#     :component => "UserService",
#        :action => "create_user",
#          :data => {
#         :user_id => 123,
#            :email => "user@example.com"
#     },
#     :timestamp => 2024-01-15 10:30:45 -0800
# }
# [DEBUG] UserService.create_user completed at 2024-01-15 10:30:45 -0800
```

### Application Logging

```ruby
class ApplicationLog < SmartMessage::Base
  property :level, required: true, validation: %w[DEBUG INFO WARN ERROR FATAL]
  property :message, required: true
  property :module_name
  property :timestamp, default: -> { Time.now.iso8601 }
  
  transport SmartMessage::Transport::StdoutTransport.new(
    format: :jsonl,
    file_path: '/var/log/application.log'
  )
end

# Log entries
ApplicationLog.new(
  level: "INFO",
  message: "Application started successfully",
  module_name: "Main"
).publish

ApplicationLog.new(
  level: "ERROR",
  message: "Database connection failed",
  module_name: "DatabaseConnector"
).publish

# File contents (/var/log/application.log):
# {"level":"INFO","message":"Application started successfully","module_name":"Main","timestamp":"2024-01-15T18:30:45Z"}
# {"level":"ERROR","message":"Database connection failed","module_name":"DatabaseConnector","timestamp":"2024-01-15T18:30:46Z"}
```

### Format Comparison Demo

```ruby
class DemoMessage < SmartMessage::Base
  property :first_name, description: "Person's first name"
  property :last_name, description: "Person's last name"
end

# Pretty format example
puts "=== Pretty Format ==="
DemoMessage.new(first_name: "Alice", last_name: "Johnson").tap do |msg|
  msg.transport(SmartMessage::Transport::StdoutTransport.new(format: :pretty))
end.publish

# JSON Lines format example  
puts "\n=== JSON Lines Format ==="
transport_jsonl = SmartMessage::Transport::StdoutTransport.new(format: :jsonl)
DemoMessage.new(first_name: "Bob", last_name: "Smith").tap do |msg|
  msg.transport(transport_jsonl)
end.publish
DemoMessage.new(first_name: "Carol", last_name: "Williams").tap do |msg|
  msg.transport(transport_jsonl)
end.publish

# JSON format example
puts "\n=== JSON Format ==="
transport_json = SmartMessage::Transport::StdoutTransport.new(format: :json)
DemoMessage.new(first_name: "David", last_name: "Brown").tap do |msg|
  msg.transport(transport_json)
end.publish
DemoMessage.new(first_name: "Emma", last_name: "Davis").tap do |msg|
  msg.transport(transport_json)  
end.publish
DemoMessage.new(first_name: "Frank", last_name: "Miller").tap do |msg|
  msg.transport(transport_json)
end.publish
```

### Integration Testing

```ruby
class TestMessage < SmartMessage::Base
  property :test_id, required: true
  property :expected_result
  property :actual_result
  property :status, default: 'pending'
  
  transport SmartMessage::Transport::StdoutTransport.new(
    format: :jsonl,
    file_path: '/tmp/test_results.log',
    loopback: true
  )
  
  def process
    self.status = (expected_result == actual_result) ? 'passed' : 'failed'
    puts "Test #{test_id}: #{status}"
  end
end

# Test execution
TestMessage.new(
  test_id: "AUTH_001",
  expected_result: "authenticated",
  actual_result: "authenticated"
).publish

# Outputs to both file and console via loopback processing
```

## File Output Management

### Automatic Directory Creation

```ruby
# Creates parent directories automatically
transport = SmartMessage::Transport::StdoutTransport.new(
  file_path: '/var/log/app/events/user_actions.log',
  auto_create_dirs: true  # Creates /var/log/app/events/ if needed
)
```

### File Rotation and Management

```ruby
# Daily log rotation example
class DailyLogger < SmartMessage::Base
  property :event, required: true
  property :data
  
  def self.current_log_path
    date_str = Time.now.strftime("%Y-%m-%d")
    "/var/log/app/daily/#{date_str}.log"
  end
  
  transport SmartMessage::Transport::StdoutTransport.new(
    format: :jsonl,
    file_path: current_log_path
  )
end

# Each day's events go to separate files
DailyLogger.new(event: "user_login", data: { user_id: 123 }).publish
```

## API Reference

### Instance Methods

#### `#format`
Returns the current output format.

```ruby
transport = SmartMessage::Transport::StdoutTransport.new(format: :jsonl)
puts transport.format  # => :jsonl
```

#### `#file_path`
Returns the configured file path (nil for STDOUT).

```ruby
transport = SmartMessage::Transport::StdoutTransport.new(file_path: '/tmp/output.log')
puts transport.file_path  # => '/tmp/output.log'
```

#### `#loopback?`
Checks if loopback processing is enabled.

```ruby
transport = SmartMessage::Transport::StdoutTransport.new(loopback: true)
puts transport.loopback?  # => true
```

#### `#publish(message)`
Publishes a message object with the configured format.

```ruby
transport.publish(message_instance)
```

## Performance Characteristics

- **Latency**: ~1ms (I/O dependent)
- **Throughput**: Limited by I/O operations (console/file writes)
- **Memory Usage**: Minimal (immediate output)
- **Threading**: Thread-safe file operations
- **Format Overhead**: Pretty > JSON Lines > JSON

## Use Cases

### Development Environment

```ruby
# config/environments/development.rb
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::StdoutTransport.new(
    format: :pretty,
    loopback: true
  )
  config.logger.level = Logger::DEBUG
end
```

### Testing Environment

```ruby
# config/environments/test.rb
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::StdoutTransport.new(
    format: :jsonl,
    file_path: Rails.root.join('tmp', 'test_messages.log')
  )
end
```

### CI/CD Pipeline Integration

```ruby
class CIMessage < SmartMessage::Base
  property :stage, required: true
  property :status, required: true
  property :duration
  property :details
  
  transport SmartMessage::Transport::StdoutTransport.new(
    format: :jsonl,
    file_path: ENV['CI_LOG_PATH'] || '/tmp/ci_pipeline.log'
  )
end

# CI stages can publish structured logs
CIMessage.new(
  stage: "build",
  status: "success", 
  duration: 45.2,
  details: { artifacts: 3, warnings: 0 }
).publish
```

### Microservices Debugging

```ruby
class ServiceMessage < SmartMessage::Base
  property :service_name, required: true
  property :operation, required: true
  property :request_id
  property :response_time
  property :status_code
  
  transport SmartMessage::Transport::StdoutTransport.new(
    format: :pretty,
    loopback: false
  )
end

# Service calls generate readable debug output
ServiceMessage.new(
  service_name: "UserService",
  operation: "authenticate",
  request_id: "req_123",
  response_time: 23.4,
  status_code: 200
).publish
```

## Best Practices

### Development
- Use `:pretty` format for interactive debugging
- Enable `loopback` to process messages locally
- Use descriptive property names for clarity

### Production Logging
- Use `:jsonl` format for structured logs
- Specify file paths with rotation patterns
- Disable `loopback` unless local processing needed

### Testing
- Use file output to capture test message flows
- Use `:json` format for minimal output
- Clear log files between test runs

### Performance
- `:json` format has lowest overhead
- Console output is slower than file output
- Consider asynchronous logging for high-volume scenarios

## Thread Safety

STDOUT Transport is fully thread-safe:
- File operations use proper locking
- Format operations are stateless
- Multiple threads can publish concurrently

```ruby
# Thread-safe concurrent publishing
threads = []
10.times do |i|
  threads << Thread.new do
    100.times do |j|
      LogMessage.new(
        level: "INFO",
        message: "Thread #{i}, Message #{j}"
      ).publish
    end
  end
end
threads.each(&:join)
```

## Error Handling

```ruby
class ErrorMessage < SmartMessage::Base
  property :error_type, required: true
  property :error_message, required: true
  property :stack_trace
  
  transport SmartMessage::Transport::StdoutTransport.new(
    format: :jsonl,
    file_path: '/var/log/errors.log'
  )
  
  def process
    # Handle error processing
    case error_type
    when 'critical'
      send_alert(error_message)
    when 'warning'
      log_warning(error_message)
    end
  end
end

begin
  risky_operation()
rescue => e
  ErrorMessage.new(
    error_type: 'critical',
    error_message: e.message,
    stack_trace: e.backtrace.join("\n")
  ).publish
end
```

## Migration Patterns

### From Console to File Logging

```ruby
# Development: Console output
transport = SmartMessage::Transport::StdoutTransport.new(format: :pretty)

# Production: File logging  
transport = SmartMessage::Transport::StdoutTransport.new(
  format: :jsonl,
  file_path: '/var/log/production.log'
)
```

### Format Evolution

```ruby
# Start with pretty format for development
# Move to JSONL for production structured logging
# Upgrade to specialized transports (Redis) for distribution

case Rails.env
when 'development'
  SmartMessage::Transport::StdoutTransport.new(format: :pretty, loopback: true)
when 'test'  
  SmartMessage::Transport::StdoutTransport.new(format: :jsonl, file_path: 'tmp/test.log')
when 'production'
  SmartMessage::Transport::RedisTransport.new(url: ENV['REDIS_URL'])
end
```

## Examples

The STDOUT Transport is demonstrated in:
- **[examples/memory/06_stdout_publish_only.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/06_stdout_publish_only.rb)** - Comprehensive format demonstration with all three output formats

### Running Examples

```bash
# Navigate to SmartMessage directory
cd smart_message

# Run the STDOUT Transport format demo
ruby examples/memory/06_stdout_publish_only.rb

# Shows all three formats:
# - Pretty format output
# - JSON Lines format output  
# - Compact JSON format output
```

## Related Documentation

- [File Transport](file-transport.md) - Base transport implementation
- [Transport Overview](../reference/transports.md) - All available transports
- [Memory Transport](memory-transport.md) - In-memory development transport
- [Troubleshooting Guide](../development/troubleshooting.md) - Testing and debugging strategies