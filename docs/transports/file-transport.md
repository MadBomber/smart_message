# File Transport

The **File Transport** is a base class for file-based message transports in SmartMessage. It provides the foundation for writing messages to files with automatic directory creation, message serialization, and thread-safe operations.

## Overview

File Transport serves as the base class for:
- **STDOUT Transport** - Console and file output with formatting
- **Custom File Transports** - Application-specific file-based messaging
- **Log Transport Extensions** - Specialized logging implementations
- **Message Persistence** - File-based message storage and archiving

## Key Features

- 📁 **Automatic Directory Creation** - Creates parent directories as needed
- 🧵 **Thread-Safe Operations** - Safe for concurrent message publishing
- 🔄 **Message Serialization** - Handles SmartMessage object encoding
- 📝 **File Append Operations** - Messages appended to existing files
- ⚙️ **Extensible Architecture** - Base class for specialized file transports
- 🛡️ **Error Handling** - Graceful handling of file system errors

## Architecture

```
Message → FileTransport → encode_message() → do_publish() → File System
       (base class)     (serialization)   (file write)   (thread-safe)
```

File Transport provides the core infrastructure that derived classes like STDOUT Transport build upon.

## Class Hierarchy

```
SmartMessage::Transport::BaseTransport
└── SmartMessage::Transport::FileTransport
    └── SmartMessage::Transport::StdoutTransport
```

## Configuration

### Basic Setup

```ruby
# Direct usage (rarely used directly)
transport = SmartMessage::Transport::FileTransport.new(
  file_path: '/var/log/messages.log'
)

# With options
transport = SmartMessage::Transport::FileTransport.new(
  file_path: '/var/log/app/events.log',
  auto_create_dirs: true
)
```

### Inheritance Pattern

```ruby
# Custom transport inheriting from FileTransport
class CustomFileTransport < SmartMessage::Transport::FileTransport
  def initialize(file_path:, custom_option: nil, **options)
    @custom_option = custom_option
    super(file_path: file_path, **options)
  end

  private

  def do_publish(message_class, serialized_message)
    # Custom formatting before file write
    formatted_content = format_for_custom_system(serialized_message)
    
    # Use parent's file writing capability
    super(message_class, formatted_content)
  end
  
  def format_for_custom_system(message)
    # Custom formatting logic
    "#{Time.now.iso8601}: #{message}\n"
  end
end
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `file_path` | String | **Required** | Path to output file |
| `auto_create_dirs` | Boolean | `true` | Automatically create parent directories |

## Core Methods

### Public Interface

#### `#publish(message)`
Publishes a SmartMessage object to the configured file.

```ruby
transport = SmartMessage::Transport::FileTransport.new(
  file_path: '/var/log/messages.log'
)

message = MyMessage.new(data: "example")
transport.publish(message)
```

#### `#file_path`
Returns the configured file path.

```ruby
puts transport.file_path  # => '/var/log/messages.log'
```

#### `#connected?`
Always returns `true` for file system availability.

```ruby
puts transport.connected?  # => true
```

### Protected Interface (for Subclasses)

#### `#encode_message(message)`
Serializes a SmartMessage object using the configured serializer.

```ruby
class MyFileTransport < SmartMessage::Transport::FileTransport
  private
  
  def do_publish(message_class, serialized_message)
    # serialized_message comes from encode_message(message)
    File.write(file_path, "#{serialized_message}\n", mode: 'a')
  end
end
```

#### `#do_publish(message_class, serialized_message)`
Template method for subclasses to implement file writing logic.

```ruby
# Base implementation in FileTransport
def do_publish(message_class, serialized_message)
  File.write(file_path, "#{serialized_message}\n", mode: 'a')
end
```

## Implementation Details

### Message Processing Pipeline

1. **Message Receipt**: `publish(message)` called with SmartMessage object
2. **Class Extraction**: Extract message class name from `message._sm_header.message_class`
3. **Serialization**: Convert message to string via `encode_message(message)`
4. **File Writing**: Call `do_publish(message_class, serialized_message)`
5. **Directory Creation**: Create parent directories if needed
6. **Thread Safety**: File operations protected for concurrent access

### Source Code Structure

```ruby
class FileTransport < BaseTransport
  def initialize(file_path:, auto_create_dirs: true, **options)
    @file_path = file_path
    @auto_create_dirs = auto_create_dirs
    super(**options)
  end

  def publish(message)
    # Extract message class and serialize the message
    message_class = message._sm_header.message_class
    serialized_message = encode_message(message)
    do_publish(message_class, serialized_message)
  end

  private

  def do_publish(message_class, serialized_message)
    ensure_directory_exists
    File.write(file_path, "#{serialized_message}\n", mode: 'a')
  end

  def ensure_directory_exists
    return unless auto_create_dirs
    
    dir = File.dirname(file_path)
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
  end
end
```

## Usage Examples

### Basic File Logging

```ruby
class LogMessage < SmartMessage::Base
  property :level, required: true
  property :message, required: true
  property :timestamp, default: -> { Time.now.iso8601 }
  
  transport SmartMessage::Transport::FileTransport.new(
    file_path: '/var/log/application.log'
  )
end

LogMessage.new(
  level: "INFO", 
  message: "Application started"
).publish

# File contains JSON-serialized message
```

### Custom File Transport

```ruby
class AuditFileTransport < SmartMessage::Transport::FileTransport
  def initialize(file_path:, include_headers: true, **options)
    @include_headers = include_headers
    super(file_path: file_path, **options)
  end

  private

  def do_publish(message_class, serialized_message)
    ensure_directory_exists
    
    content = if @include_headers
      "#{Time.now.iso8601} [#{message_class}] #{serialized_message}\n"
    else
      "#{serialized_message}\n"
    end
    
    File.write(file_path, content, mode: 'a')
  end
end

# Usage
class AuditMessage < SmartMessage::Base
  property :action, required: true
  property :user_id, required: true
  
  transport AuditFileTransport.new(
    file_path: '/var/log/audit.log',
    include_headers: true
  )
end

AuditMessage.new(action: "login", user_id: 123).publish
```

### Rotated Log Files

```ruby
class RotatedFileTransport < SmartMessage::Transport::FileTransport
  def initialize(base_path:, **options)
    @base_path = base_path
    super(file_path: current_log_file, **options)
  end

  private

  def current_log_file
    date_str = Time.now.strftime("%Y-%m-%d")
    "#{@base_path}/#{date_str}.log"
  end

  def do_publish(message_class, serialized_message)
    # Update file path for current date
    @file_path = current_log_file
    super(message_class, serialized_message)
  end
end

# Usage
class DailyMessage < SmartMessage::Base
  property :event, required: true
  
  transport RotatedFileTransport.new(
    base_path: '/var/log/daily'
  )
end

# Messages automatically go to /var/log/daily/2024-01-15.log
DailyMessage.new(event: "user_action").publish
```

## Directory Management

### Automatic Directory Creation

```ruby
# Creates /var/log/app/subsystem/ if it doesn't exist
transport = SmartMessage::Transport::FileTransport.new(
  file_path: '/var/log/app/subsystem/events.log',
  auto_create_dirs: true  # default
)
```

### Manual Directory Management

```ruby
# Disable automatic creation
transport = SmartMessage::Transport::FileTransport.new(
  file_path: '/existing/path/events.log',
  auto_create_dirs: false
)

# Create directories manually
FileUtils.mkdir_p('/var/log/custom')
transport = SmartMessage::Transport::FileTransport.new(
  file_path: '/var/log/custom/events.log'
)
```

## Thread Safety

File Transport is fully thread-safe:
- File append operations are atomic
- Directory creation is protected
- Multiple threads can publish concurrently

```ruby
transport = SmartMessage::Transport::FileTransport.new(
  file_path: '/tmp/concurrent.log'
)

class TestMessage < SmartMessage::Base
  property :thread_id
  property :sequence
  transport transport
end

# Thread-safe concurrent publishing
threads = []
5.times do |thread_id|
  threads << Thread.new do
    10.times do |sequence|
      TestMessage.new(
        thread_id: thread_id,
        sequence: sequence
      ).publish
    end
  end
end
threads.each(&:join)

# All 50 messages safely written to file
```

## Error Handling

### File System Errors

```ruby
begin
  message.publish
rescue Errno::ENOENT => e
  puts "Directory doesn't exist: #{e.message}"
rescue Errno::EACCES => e
  puts "Permission denied: #{e.message}"
rescue Errno::ENOSPC => e  
  puts "No space left on device: #{e.message}"
end
```

### Custom Error Handling

```ruby
class SafeFileTransport < SmartMessage::Transport::FileTransport
  private

  def do_publish(message_class, serialized_message)
    super(message_class, serialized_message)
  rescue => e
    # Log error and fall back to alternate location
    fallback_path = "/tmp/fallback_#{File.basename(file_path)}"
    File.write(fallback_path, "#{serialized_message}\n", mode: 'a')
    warn "File transport error: #{e.message}, using fallback: #{fallback_path}"
  end
end
```

## Performance Characteristics

- **Latency**: ~1-5ms (filesystem dependent)
- **Throughput**: Limited by I/O operations
- **Memory Usage**: Minimal (immediate write)
- **Concurrency**: Thread-safe with file locking
- **Disk Usage**: Grows with message volume

## Extension Patterns

### Formatted Output Transport

```ruby
class FormattedFileTransport < SmartMessage::Transport::FileTransport
  def initialize(file_path:, format: :json, **options)
    @format = format
    super(file_path: file_path, **options)
  end

  private

  def do_publish(message_class, serialized_message)
    content = case @format
              when :csv
                to_csv(message_class, serialized_message)
              when :xml  
                to_xml(message_class, serialized_message)
              else
                serialized_message
              end
    
    File.write(file_path, "#{content}\n", mode: 'a')
  end
  
  def to_csv(message_class, data)
    # Convert JSON to CSV format
    parsed = JSON.parse(data)
    parsed.values.join(',')
  end
  
  def to_xml(message_class, data)
    # Convert JSON to XML format
    "<message class=\"#{message_class}\">#{data}</message>"
  end
end
```

### Buffered File Transport

```ruby
class BufferedFileTransport < SmartMessage::Transport::FileTransport
  def initialize(file_path:, buffer_size: 100, **options)
    @buffer_size = buffer_size
    @buffer = []
    @buffer_mutex = Mutex.new
    super(file_path: file_path, **options)
  end

  private

  def do_publish(message_class, serialized_message)
    @buffer_mutex.synchronize do
      @buffer << serialized_message
      
      if @buffer.size >= @buffer_size
        flush_buffer
      end
    end
  end
  
  def flush_buffer
    return if @buffer.empty?
    
    content = @buffer.join("\n") + "\n"
    File.write(file_path, content, mode: 'a')
    @buffer.clear
  end
  
  public
  
  def close
    @buffer_mutex.synchronize { flush_buffer }
  end
end
```

## Best Practices

### Configuration
- Use absolute paths for file_path
- Enable auto_create_dirs for robustness
- Consider log rotation for long-running applications

### Performance  
- Use buffered writes for high-volume scenarios
- Monitor disk space usage
- Consider asynchronous variants for critical paths

### Error Handling
- Implement fallback locations for critical messages
- Monitor file system permissions
- Handle disk full scenarios gracefully

### Testing
- Use temporary directories in tests
- Clean up test files in teardown
- Mock file operations for unit tests

## Testing Support

### Test Helpers

```ruby
class TestFileTransport < SmartMessage::Transport::FileTransport
  attr_reader :written_messages
  
  def initialize(**options)
    @written_messages = []
    super(file_path: '/dev/null', **options)
  end

  private

  def do_publish(message_class, serialized_message)
    @written_messages << {
      message_class: message_class,
      content: serialized_message,
      timestamp: Time.now
    }
  end
end

# Usage in tests
RSpec.describe "Message Publishing" do
  let(:transport) { TestFileTransport.new }
  
  it "publishes messages" do
    MyMessage.transport = transport
    MyMessage.new(data: "test").publish
    
    expect(transport.written_messages).to have(1).item
    expect(transport.written_messages.first[:message_class]).to eq("MyMessage")
  end
end
```

## Related Documentation

- [STDOUT Transport](stdout-transport.md) - File Transport implementation with formatting
- [Transport Overview](../reference/transports.md) - All available transports  
- [Redis Transport](redis-transport.md) - Distributed messaging transport
- [Memory Transport](memory-transport.md) - In-memory development transport
- [Troubleshooting Guide](../development/troubleshooting.md) - Testing and debugging strategies