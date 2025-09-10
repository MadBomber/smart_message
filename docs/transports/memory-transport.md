# Memory Transport

The **Memory Transport** is an in-memory transport implementation designed for testing, development, and rapid prototyping. It stores messages in memory and provides synchronous processing capabilities.

## Overview

The Memory Transport is perfect for:
- **Unit testing** - No external dependencies required
- **Local development** - Fast, lightweight message processing
- **Rapid prototyping** - Quick setup without infrastructure
- **Debug and inspection** - Full visibility into message flow

## Key Features

- 🧠 **In-Memory Storage** - Messages stored in process memory
- ⚡ **Synchronous Processing** - Immediate message processing
- 🔍 **Message Inspection** - View and count stored messages
- 🔄 **Auto-Processing** - Optional automatic message processing
- 🛡️ **Memory Protection** - Configurable message limits to prevent overflow
- 🧵 **Thread-Safe** - Mutex-protected operations

## Configuration

### Basic Setup

```ruby
# Minimal configuration
transport = SmartMessage::Transport::MemoryTransport.new

# With options
transport = SmartMessage::Transport::MemoryTransport.new(
  auto_process: true,     # Process messages immediately (default: true)
  max_messages: 1000      # Maximum messages to store (default: 1000)
)
```

### Using with SmartMessage

```ruby
# Configure as default transport
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::MemoryTransport.new
end

# Use in message class
class TestMessage < SmartMessage::Base
  property :content, required: true
  
  transport :memory
  
  def process
    puts "Processing: #{content}"
  end
end
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `auto_process` | Boolean | `true` | Automatically process messages when published |
| `max_messages` | Integer | `1000` | Maximum messages to store (prevents memory overflow) |

## Usage Examples

### Basic Message Processing

```ruby
# Create transport
transport = SmartMessage::Transport::MemoryTransport.new

# Define message
class AlertMessage < SmartMessage::Base
  property :message, required: true
  property :severity, default: 'info'
  
  transport transport
  
  def process
    puts "[#{severity.upcase}] #{message}"
  end
end

# Publish message
AlertMessage.new(
  message: "System startup complete",
  severity: "info"
).publish

# Output: [INFO] System startup complete
```

### Manual Processing Control

```ruby
# Disable auto-processing for batch operations
transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)

class DataMessage < SmartMessage::Base
  property :data
  transport transport
  
  def process
    puts "Processing: #{data}"
  end
end

# Publish multiple messages
DataMessage.new(data: "batch 1").publish
DataMessage.new(data: "batch 2").publish
DataMessage.new(data: "batch 3").publish

puts "Messages stored: #{transport.message_count}"
# Output: Messages stored: 3

# Process all at once
transport.process_all
# Output: 
# Processing: batch 1
# Processing: batch 2
# Processing: batch 3
```

### Message Inspection

```ruby
transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)

class OrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :amount, required: true
  transport transport
end

# Publish test messages
OrderMessage.new(order_id: "ORD-001", amount: 99.99).publish
OrderMessage.new(order_id: "ORD-002", amount: 149.50).publish

# Inspect stored messages
puts "Total messages: #{transport.message_count}"
transport.all_messages.each_with_index do |msg, index|
  puts "Message #{index + 1}: #{msg[:message_class]} at #{msg[:published_at]}"
end

# Clear messages when done
transport.clear_messages
puts "Messages after clear: #{transport.message_count}"
```

## API Reference

### Instance Methods

#### `#message_count`
Returns the number of messages currently stored.

```ruby
count = transport.message_count
puts "Stored messages: #{count}"
```

#### `#all_messages`
Returns a copy of all stored messages with metadata.

```ruby
messages = transport.all_messages
messages.each do |msg|
  puts "Class: #{msg[:message_class]}"
  puts "Time: #{msg[:published_at]}"
  puts "Data: #{msg[:serialized_message]}"
end
```

#### `#clear_messages`
Removes all stored messages from memory.

```ruby
transport.clear_messages
```

#### `#process_all`
Manually processes all stored messages (useful when `auto_process: false`).

```ruby
# Publish messages without auto-processing
transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
# ... publish messages ...

# Process them all at once
transport.process_all
```

#### `#connected?`
Always returns `true` since memory transport is always available.

```ruby
puts transport.connected?  # => true
```

## Use Cases

### Unit Testing

```ruby
RSpec.describe "Message Processing" do
  let(:transport) { SmartMessage::Transport::MemoryTransport.new }
  
  before do
    MyMessage.transport = transport
    transport.clear_messages
  end
  
  it "processes messages correctly" do
    MyMessage.new(data: "test").publish
    expect(transport.message_count).to eq(1)
  end
  
  it "respects message limits" do
    transport = SmartMessage::Transport::MemoryTransport.new(max_messages: 2)
    
    3.times { |i| MyMessage.new(data: i).publish }
    expect(transport.message_count).to eq(2)  # Oldest message dropped
  end
end
```

### Development Environment

```ruby
# config/environments/development.rb
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::MemoryTransport.new(
    auto_process: true,
    max_messages: 500
  )
  config.logger.level = Logger::DEBUG  # See all message activity
end
```

### Batch Processing

```ruby
# Collect messages for batch processing
transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)

# Publish work items
work_items.each do |item|
  WorkMessage.new(item: item).publish
end

# Process batch when ready
puts "Processing #{transport.message_count} work items..."
start_time = Time.now
transport.process_all
puts "Completed in #{Time.now - start_time} seconds"
```

## Performance Characteristics

- **Latency**: ~0.01ms (memory access)
- **Throughput**: 100K+ messages/second
- **Memory Usage**: ~1KB per stored message
- **Concurrency**: Thread-safe with mutex protection
- **Persistence**: None (messages lost when process ends)

## Best Practices

### Testing
- Use `clear_messages` in test setup/teardown
- Set reasonable `max_messages` limits for long-running tests
- Disable `auto_process` for message inspection tests

### Development
- Enable debug logging to see message flow
- Use message inspection methods for debugging
- Consider memory limits in long-running development processes

### Production
⚠️ **Not recommended for production use**
- Messages are lost when process restarts
- No persistence or durability guarantees
- Limited by process memory

## Thread Safety

The Memory Transport is fully thread-safe:
- All operations use mutex synchronization
- Messages can be published from multiple threads
- Inspection methods return safe copies

```ruby
# Thread-safe concurrent publishing
threads = []
10.times do |i|
  threads << Thread.new do
    100.times { |j| TestMessage.new(data: "#{i}-#{j}").publish }
  end
end
threads.each(&:join)

puts "Total messages: #{transport.message_count}"  # Always accurate
```

## Migration from Memory Transport

When moving from Memory Transport to production transports:

```ruby
# Development (Memory Transport)
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::MemoryTransport.new
end

# Production (Redis Transport)
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::RedisTransport.new(
    url: ENV['REDIS_URL']
  )
end
```

Messages and processing logic remain identical - only the transport configuration changes.

## Examples

The `examples/memory/` directory contains comprehensive, runnable examples demonstrating Memory Transport capabilities:

### Core Messaging Examples
- **[03_point_to_point_orders.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/03_point_to_point_orders.rb)** - Point-to-point order processing with payment integration
- **[04_publish_subscribe_events.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/04_publish_subscribe_events.rb)** - Event broadcasting to multiple services (email, SMS, audit)
- **[05_many_to_many_chat.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/05_many_to_many_chat.rb)** - Interactive chat system with rooms, bots, and human agents

### Advanced Features
- **[01_message_deduplication_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/01_message_deduplication_demo.rb)** - Message deduplication patterns and strategies
- **[02_dead_letter_queue_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/02_dead_letter_queue_demo.rb)** - Complete Dead Letter Queue system with circuit breakers
- **[07_proc_handlers_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/07_proc_handlers_demo.rb)** - Flexible message handlers (blocks, procs, lambdas, methods)

### Configuration & Monitoring
- **[08_custom_logger_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/08_custom_logger_demo.rb)** - Advanced logging with SmartMessage::Logger::Default
- **[09_error_handling_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/09_error_handling_demo.rb)** - Comprehensive validation, version mismatch, and error handling
- **[13_header_block_configuration.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/13_header_block_configuration.rb)** - Header and block configuration examples
- **[14_global_configuration_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/14_global_configuration_demo.rb)** - Global configuration management
- **[15_logger_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/15_logger_demo.rb)** - Advanced logging demonstrations

### Entity Addressing & Filtering
- **[10_entity_addressing_basic.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/10_entity_addressing_basic.rb)** - Basic FROM/TO/REPLY_TO message addressing
- **[11_entity_addressing_with_filtering.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/11_entity_addressing_with_filtering.rb)** - Advanced entity-aware message filtering
- **[12_regex_filtering_microservices.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/12_regex_filtering_microservices.rb)** - Advanced regex filtering for microservices

### Visual Demonstrations
- **[06_stdout_publish_only.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/06_stdout_publish_only.rb)** - STDOUT transport publish-only demonstration with logging and metrics examples
- **[16_pretty_print_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/memory/16_pretty_print_demo.rb)** - Message inspection and pretty-printing capabilities

### Running Examples

```bash
# Navigate to the SmartMessage directory
cd smart_message

# Run any Memory Transport example
ruby examples/memory/03_point_to_point_orders.rb
ruby examples/memory/05_many_to_many_chat.rb
ruby examples/memory/02_dead_letter_queue_demo.rb

# Or explore the entire directory
ls examples/memory/
```

Each example is self-contained and demonstrates specific Memory Transport features with clear educational comments and real-world scenarios.

## Related Documentation

- [Transport Overview](../reference/transports.md) - All available transports
- [Redis Transport](redis-transport.md) - Production-ready Redis transport
- [Testing Guide](../development/troubleshooting.md) - Testing strategies with SmartMessage