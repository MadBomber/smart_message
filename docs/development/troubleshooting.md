# Troubleshooting Guide

This guide helps you diagnose and solve common issues when working with SmartMessage.

## Common Issues

### 1. Messages Not Being Processed

**Symptoms:**
- Messages are published but process methods are never called
- No errors are thrown
- Statistics show messages published but not routed

**Possible Causes & Solutions:**

#### Missing Subscription
```ruby
# Problem: Forgot to subscribe
class MyMessage < SmartMessage::Base
  property :data
  
  def self.process(header, payload)
    puts "Processing message"
  end
end

MyMessage.new(data: "test").publish  # Nothing happens

# Solution: Add subscription
MyMessage.subscribe
MyMessage.new(data: "test").publish  # Now it works
```

#### Transport Not Configured for Loopback
```ruby
# Problem: Using STDOUT without loopback
class MyMessage < SmartMessage::Base
  property :data
  
  config do
    transport SmartMessage::Transport.create(:stdout)  # No loopback
    serializer SmartMessage::Serializer::Json.new
  end
end

# Solution: Enable loopback for local testing
class MyMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::Json.new
  end
end
```

#### Auto-process Disabled
```ruby
# Problem: Memory transport with auto_process disabled
class MyMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:memory, auto_process: false)
  end
end

# Messages are stored but not processed
transport = MyMessage.transport
puts transport.message_count  # Shows stored messages

# Solution: Enable auto_process or manually process
MyMessage.config do
  transport SmartMessage::Transport.create(:memory, auto_process: true)
end

# Or manually trigger processing
transport.process_all
```

### 2. Serialization Errors

**Symptoms:**
- `SmartMessage::Errors::SerializerNotConfigured` exceptions
- Encoding/decoding failures
- Malformed message data

**Solutions:**

#### Missing Serializer Configuration
```ruby
# Problem: No serializer configured
class MyMessage < SmartMessage::Base
  property :data
  
  config do
    transport SmartMessage::Transport.create(:memory)
    # Missing serializer!
  end
end

# Throws: SmartMessage::Errors::SerializerNotConfigured
MyMessage.new(data: "test").publish

# Solution: Add serializer
class MyMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:memory)
    serializer SmartMessage::Serializer::Json.new
  end
end
```

#### JSON Encoding Issues
```ruby
# Problem: Objects that can't be serialized to JSON
class ProblematicMessage < SmartMessage::Base
  property :data
  
  config do
    serializer SmartMessage::Serializer::Json.new
  end
end

# This will fail
message = ProblematicMessage.new(data: Object.new)
message.publish  # JSON::GeneratorError

# Solution: Ensure data is JSON-serializable
message = ProblematicMessage.new(data: { key: "value" })
message.publish  # Works fine

# Or implement custom serialization
class SafeMessage < SmartMessage::Base
  property :data
  
  def to_h
    hash = super
    hash[:data] = hash[:data].to_s if hash[:data]
    hash
  end
end
```

### 3. Transport Configuration Issues

**Symptoms:**
- `SmartMessage::Errors::TransportNotConfigured` exceptions
- Connection failures
- Messages not being sent

**Solutions:**

#### Missing Transport Configuration
```ruby
# Problem: No transport configured
class MyMessage < SmartMessage::Base
  property :data
  
  config do
    serializer SmartMessage::Serializer::Json.new
    # Missing transport!
  end
end

MyMessage.new(data: "test").publish  # Throws TransportNotConfigured

# Solution: Add transport
class MyMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:memory)
    serializer SmartMessage::Serializer::Json.new
  end
end
```

#### Transport Connection Issues
```ruby
# For custom transports that might fail to connect
class MyMessage < SmartMessage::Base
  config do
    transport CustomTransport.new(host: "unreachable-host")
  end
end

# Check transport status
transport = MyMessage.transport
puts "Connected: #{transport.connected?}"

# Solution: Verify connection settings
class MyMessage < SmartMessage::Base
  config do
    transport CustomTransport.new(
      host: "localhost",
      port: 5672,
      retry_attempts: 3
    )
  end
end
```

### 4. Thread Pool Issues

**Symptoms:**
- Messages processed very slowly
- Application hangs on exit
- High memory usage

**Debugging Thread Pool:**

```ruby
dispatcher = SmartMessage::Dispatcher.new

# Check thread pool status
status = dispatcher.status
puts "Running: #{status[:running]}"
puts "Queue length: #{status[:queue_length]}"
puts "Scheduled tasks: #{status[:scheduled_task_count]}"
puts "Completed tasks: #{status[:completed_task_count]}"
puts "Pool size: #{status[:length]}"

# If queue is growing, messages are being created faster than processed
if status[:queue_length] > 100
  puts "⚠️  Large queue detected - consider optimizing message processing"
end

# If pool is not running
unless status[:running]
  puts "❌ Thread pool is not running - check for shutdown issues"
end
```

**Solutions:**

#### Slow Message Processing
```ruby
# Problem: Slow process method blocking thread pool
class SlowMessage < SmartMessage::Base
  def self.process(header, payload)
    sleep(10)  # Very slow operation
    # Processing logic
  end
end

# Solution: Optimize or use background jobs
class OptimizedMessage < SmartMessage::Base
  def self.process(header, payload)
    # Quick validation
    data = JSON.parse(payload)
    
    # Delegate heavy work to background job
    BackgroundJob.perform_async(data)
  end
end
```

#### Application Hanging on Exit
```ruby
# Problem: Threads not shutting down gracefully
# The dispatcher handles this automatically, but if you create custom threads:

class CustomMessage < SmartMessage::Base
  def self.process(header, payload)
    # Problem: Creating non-daemon threads
    Thread.new do
      loop do
        # Long-running work
        sleep(1)
      end
    end
  end
end

# Solution: Use daemon threads or proper cleanup
class BetterMessage < SmartMessage::Base
  def self.process(header, payload)
    thread = Thread.new do
      loop do
        break if Thread.current[:stop_requested]
        # Work with interruption points
        sleep(1)
      end
    end
    
    # Register cleanup
    at_exit do
      thread[:stop_requested] = true
      thread.join(5)  # Wait up to 5 seconds
    end
  end
end
```

### 5. Memory Issues

**Symptoms:**
- Increasing memory usage over time
- Out of memory errors
- Slow performance

**Debugging Memory Usage:**

```ruby
# Check message storage in memory transport
transport = SmartMessage::Transport.create(:memory)
puts "Stored messages: #{transport.message_count}"
puts "Max messages: #{transport.instance_variable_get(:@options)[:max_messages]}"

# Check statistics storage
puts "Statistics entries: #{SS.stat.keys.length}"

# Monitor object creation
class MemoryMonitorMessage < SmartMessage::Base
  def self.process(header, payload)
    puts "Objects before: #{ObjectSpace.count_objects[:TOTAL]}"
    
    # Your processing logic
    data = JSON.parse(payload)
    
    puts "Objects after: #{ObjectSpace.count_objects[:TOTAL]}"
  end
end
```

**Solutions:**

#### Memory Transport Overflow
```ruby
# Problem: Memory transport storing too many messages
transport = SmartMessage::Transport.create(:memory, max_messages: 10000)

# Monitor and clean up
def cleanup_memory_transport(transport)
  if transport.message_count > 5000
    puts "Cleaning up old messages..."
    transport.clear_messages
  end
end

# Or use smaller limits
transport = SmartMessage::Transport.create(:memory, max_messages: 100)
```

#### Statistics Memory Growth
```ruby
# Problem: Statistics growing without bounds
# Check current statistics size
puts "Statistics size: #{SS.stat.size}"

# Solution: Periodic cleanup
def cleanup_statistics
  # Keep only recent statistics
  current_stats = SS.stat
  important_stats = current_stats.select do |key, value|
    # Keep publish counts and recent routing stats
    key.include?('publish') || value > 0
  end
  
  SS.reset
  important_stats.each { |key, value| SS.add(*key.split('+'), how_many: value) }
end

# Run cleanup periodically
Thread.new do
  loop do
    sleep(3600)  # Every hour
    cleanup_statistics
  end
end
```

### 6. Debugging Message Flow

**Enable Debug Logging:**

```ruby
# Add debug output to your message classes
class DebugMessage < SmartMessage::Base
  property :data
  
  def publish
    puts "🚀 Publishing #{self.class.name}: #{self.to_h}"
    super
  end
  
  def self.process(header, payload)
    puts "📥 Processing #{header.message_class}: #{payload}"
    
    # Your processing logic
    data = JSON.parse(payload)
    message = new(data)
    
    puts "✅ Processed #{header.message_class}: #{message.data}"
  end
end
```

**Trace Message Path:**

```ruby
# Add correlation IDs for tracing
class TrackedMessage < SmartMessage::Base
  property :data
  property :correlation_id, default: -> { SecureRandom.uuid }
  
  def publish
    puts "[#{correlation_id}] Publishing message"
    super
  end
  
  def self.process(header, payload)
    data = JSON.parse(payload)
    message = new(data)
    
    puts "[#{message.correlation_id}] Processing message"
    
    # Your logic here
    
    puts "[#{message.correlation_id}] Processing complete"
  end
end
```

**Check Statistics:**

```ruby
# Monitor message flow with statistics
def print_message_stats(message_class)
  class_name = message_class.to_s
  published = SS.get(class_name, 'publish')
  routed = SS.get(class_name, "#{class_name}.process", 'routed')
  
  puts "#{class_name} Statistics:"
  puts "  Published: #{published}"
  puts "  Routed: #{routed}"
  puts "  Success rate: #{routed.to_f / published * 100}%" if published > 0
end

# Usage
print_message_stats(MyMessage)
```

### 7. Configuration Issues

**Debug Configuration:**

```ruby
# Check current configuration
def debug_message_config(message_class)
  puts "#{message_class} Configuration:"
  puts "  Transport: #{message_class.transport.class.name}"
  puts "  Transport configured: #{message_class.transport_configured?}"
  puts "  Serializer: #{message_class.serializer.class.name}"
  puts "  Serializer configured: #{message_class.serializer_configured?}"
  
  # Check instance-level overrides
  instance = message_class.new
  puts "  Instance transport: #{instance.transport.class.name}"
  puts "  Instance serializer: #{instance.serializer.class.name}"
end

debug_message_config(MyMessage)
```

**Reset Configuration:**

```ruby
# If configuration gets corrupted, reset it
class MyMessage < SmartMessage::Base
  # Reset all configuration
  reset_transport
  reset_serializer
  reset_logger
  
  # Reconfigure
  config do
    transport SmartMessage::Transport.create(:memory)
    serializer SmartMessage::Serializer::Json.new
  end
end
```

## Performance Troubleshooting

### Slow Message Processing

```ruby
# Benchmark message processing
require 'benchmark'

def benchmark_message_processing(message_class, count = 100)
  time = Benchmark.measure do
    count.times do |i|
      message_class.new(data: "test #{i}").publish
    end
    
    # Wait for processing to complete
    sleep(1)
  end
  
  puts "Processed #{count} messages in #{time.real.round(2)} seconds"
  puts "Rate: #{(count / time.real).round(2)} messages/second"
end

benchmark_message_processing(MyMessage, 1000)
```

### High Memory Usage

```ruby
# Monitor memory during message processing
def monitor_memory_usage
  require 'objspace'
  
  initial_memory = ObjectSpace.count_objects[:TOTAL]
  
  # Process some messages
  100.times { |i| MyMessage.new(data: "test #{i}").publish }
  
  # Force garbage collection
  GC.start
  
  final_memory = ObjectSpace.count_objects[:TOTAL]
  
  puts "Memory usage:"
  puts "  Initial: #{initial_memory} objects"
  puts "  Final: #{final_memory} objects"
  puts "  Difference: #{final_memory - initial_memory} objects"
end

monitor_memory_usage
```

## Getting Help

### Collect Debug Information

```ruby
def collect_debug_info
  puts "SmartMessage Debug Information"
  puts "=============================="
  puts "Version: #{SmartMessage::VERSION}"
  puts "Ruby version: #{RUBY_VERSION}"
  puts "Platform: #{RUBY_PLATFORM}"
  puts ""
  
  # Available transports
  puts "Available transports: #{SmartMessage::Transport.available.join(', ')}"
  puts ""
  
  # Current statistics
  puts "Current statistics:"
  SS.stat.each { |key, value| puts "  #{key}: #{value}" }
  puts ""
  
  # Thread pool status if dispatcher exists
  begin
    dispatcher = SmartMessage::Dispatcher.new
    status = dispatcher.status
    puts "Dispatcher status:"
    status.each { |key, value| puts "  #{key}: #{value}" }
  rescue => e
    puts "Dispatcher error: #{e.message}"
  end
end

collect_debug_info
```

### Enable Verbose Logging

```ruby
# Enable debug output in test.log
require 'debug_me'
include DebugMe

# This will log to test.log with detailed information
debug_me { "Message published: #{message.to_h}" }
```

If you're still experiencing issues after trying these troubleshooting steps, please open an issue on the [GitHub repository](https://github.com/MadBomber/smart_message) with:

1. Your debug information (use `collect_debug_info` above)
2. A minimal code example that reproduces the issue
3. The full error message and stack trace
4. Your system environment details