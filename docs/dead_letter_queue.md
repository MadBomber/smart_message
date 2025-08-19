# Dead Letter Queue

SmartMessage includes a comprehensive file-based Dead Letter Queue (DLQ) system for capturing, storing, and replaying failed messages. The DLQ provides production-grade reliability with automatic integration into the circuit breaker system.

## Overview

The Dead Letter Queue serves as a safety net for your messaging system:

- **Automatic Capture**: Failed messages are automatically stored when circuit breakers trip
- **Manual Capture**: Explicitly store messages that fail business logic validation
- **Replay Capabilities**: Retry failed messages individually, in batches, or all at once
- **Transport Override**: Replay messages through a different transport than originally configured
- **Administrative Tools**: Filter, analyze, and export messages for debugging
- **Thread-Safe**: All operations are protected with mutex for concurrent access

## File Format

The DLQ uses JSON Lines (.jsonl) format - one JSON object per line:

```json
{"timestamp":"2025-08-19T10:30:45Z","header":{...},"payload":"...","error":"Connection timeout","retry_count":0,"transport":"Redis","stack_trace":"..."}
{"timestamp":"2025-08-19T10:31:12Z","header":{...},"payload":"...","error":"Circuit breaker open","retry_count":1,"transport":"Redis","stack_trace":"..."}
```

Benefits of JSON Lines:
- Append-only for efficient writes
- Line-by-line processing for memory efficiency
- Human-readable for debugging
- Easy to process with standard Unix tools

## Configuration

### Global Default Configuration

Configure a default DLQ that all components will use:

```ruby
# Set default path for all DLQ operations
SmartMessage::DeadLetterQueue.configure_default('/var/log/app/dlq.jsonl')

# Access the default instance anywhere
dlq = SmartMessage::DeadLetterQueue.default
```

### Environment-Based Configuration

Use environment variables for different deployments:

```ruby
# In your application initialization
SmartMessage::DeadLetterQueue.configure_default(
  ENV.fetch('SMART_MESSAGE_DLQ_PATH', 'dead_letters.jsonl')
)
```

### Per-Environment Configuration

Configure different paths for each environment:

```ruby
# config/initializers/smart_message.rb (Rails example)
case Rails.env
when 'production'
  SmartMessage::DeadLetterQueue.configure_default('/var/log/smart_message/production_dlq.jsonl')
when 'staging'
  SmartMessage::DeadLetterQueue.configure_default('/var/log/smart_message/staging_dlq.jsonl')
else
  SmartMessage::DeadLetterQueue.configure_default('tmp/development_dlq.jsonl')
end
```

### Custom Instances

Create separate DLQ instances for different purposes:

```ruby
# Critical failures need special handling
critical_dlq = SmartMessage::DeadLetterQueue.new('/var/log/critical_failures.jsonl')

# Separate DLQ for payment messages
payment_dlq = SmartMessage::DeadLetterQueue.new('/var/log/payment_failures.jsonl')

# Temporary DLQ for testing
test_dlq = SmartMessage::DeadLetterQueue.new('/tmp/test_failures.jsonl')
```

## Core Operations

### FIFO Queue Operations

The DLQ operates as a First-In-First-Out queue:

```ruby
dlq = SmartMessage::DeadLetterQueue.default

# Add a failed message
entry = dlq.enqueue(
  message_header,      # SmartMessage::Header object
  message_payload,     # Serialized message string
  error: "Connection timeout",
  retry_count: 0,
  transport: "Redis",
  stack_trace: exception.backtrace.join("\n")
)

# Check queue size
puts "Messages in queue: #{dlq.size}"

# Peek at the oldest message without removing it
next_message = dlq.peek
puts "Next for replay: #{next_message[:header][:message_class]}"

# Remove and get the oldest message
message = dlq.dequeue
process_message(message) if message

# Clear all messages
dlq.clear
```

### Message Structure

Each DLQ entry contains:

```ruby
{
  timestamp: "2025-08-19T10:30:45Z",        # When the failure occurred
  header: {                                 # Complete message header
    uuid: "abc-123",
    message_class: "OrderMessage",
    published_at: "2025-08-19T10:30:40Z",
    publisher_pid: 12345,
    version: 1,
    from: "order-service",
    to: "payment-service",
    reply_to: "order-service"
  },
  payload: '{"order_id":"123","amount":99.99}',  # Original message payload
  payload_format: "json",                   # Serialization format
  error: "Connection refused",              # Error message
  retry_count: 2,                           # Number of retry attempts
  transport: "Redis",                       # Transport that failed
  stack_trace: "..."                        # Full stack trace (optional)
}
```

## Replay Capabilities

### Individual Message Replay

Replay the oldest message:

```ruby
result = dlq.replay_one
if result[:success]
  puts "Message replayed successfully"
else
  puts "Replay failed: #{result[:error]}"
end
```

### Batch Replay

Replay multiple messages:

```ruby
# Replay next 10 messages
results = dlq.replay_batch(10)
puts "Successful: #{results[:success]}"
puts "Failed: #{results[:failed]}"
results[:errors].each do |error|
  puts "Error: #{error}"
end
```

### Full Queue Replay

Replay all messages:

```ruby
results = dlq.replay_all
puts "Replayed #{results[:success]} messages"
puts "Failed to replay #{results[:failed]} messages"
```

### Transport Override

Replay through a different transport:

```ruby
# Original message used Redis, replay through RabbitMQ
rabbit_transport = SmartMessage::Transport.create(:rabbitmq)

# Replay one with override
dlq.replay_one(rabbit_transport)

# Replay batch with override
dlq.replay_batch(10, rabbit_transport)

# Replay all with override
dlq.replay_all(rabbit_transport)
```

## Administrative Functions

### Message Filtering

Filter messages for analysis:

```ruby
# Find all failed OrderMessage instances
order_failures = dlq.filter_by_class('OrderMessage')
puts "Found #{order_failures.size} failed orders"

# Find all timeout errors
timeout_errors = dlq.filter_by_error_pattern(/timeout/i)
timeout_errors.each do |entry|
  puts "Timeout at #{entry[:timestamp]}: #{entry[:error]}"
end

# Find connection errors
connection_errors = dlq.filter_by_error_pattern('Connection refused')
```

### Statistics

Get queue statistics:

```ruby
stats = dlq.statistics
puts "Total messages: #{stats[:total]}"

# Breakdown by message class
stats[:by_class].each do |klass, count|
  puts "#{klass}: #{count} failures"
end

# Breakdown by error type
stats[:by_error].sort_by { |_, count| -count }.first(5).each do |error, count|
  puts "#{error}: #{count} occurrences"
end
```

### Time-Based Export

Export messages within a time range:

```ruby
# Get failures from the last hour
one_hour_ago = Time.now - 3600
recent_failures = dlq.export_range(one_hour_ago, Time.now)

# Get failures from yesterday
yesterday_start = Time.now - 86400
yesterday_end = Time.now - 1
yesterday_failures = dlq.export_range(yesterday_start, yesterday_end)

# Export for analysis
File.write('failures_export.json', recent_failures.to_json)
```

### Message Inspection

Inspect messages without removing them:

```ruby
# Look at next 10 messages
messages = dlq.inspect_messages(limit: 10)
messages.each do |msg|
  puts "#{msg[:timestamp]} - #{msg[:header][:message_class]}: #{msg[:error]}"
end

# Default limit is 10
dlq.inspect_messages.each do |msg|
  analyze_failure(msg)
end
```

## Integration with Circuit Breakers

The DLQ is automatically integrated with SmartMessage's circuit breaker system:

### Automatic Capture

When circuit breakers trip, messages are automatically sent to the DLQ:

```ruby
class PaymentMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:redis)
    # Circuit breaker configured automatically
  end
end

# If Redis is down, circuit breaker trips and message goes to DLQ
message = PaymentMessage.new(amount: 100.00)
begin
  message.publish
rescue => e
  # Message is already in DLQ via circuit breaker
  puts "Message saved to DLQ"
end
```

### Manual Circuit Breaker Integration

Configure custom circuit breakers with DLQ fallback:

```ruby
class CriticalService
  include BreakerMachines::DSL
  
  circuit :external_api do
    threshold failures: 3, within: 60.seconds
    reset_after 30.seconds
    
    # Use custom DLQ for critical failures
    custom_dlq = SmartMessage::DeadLetterQueue.new('/var/log/critical.jsonl')
    fallback SmartMessage::CircuitBreaker::Fallbacks.dead_letter_queue(custom_dlq)
  end
  
  def call_api(message)
    circuit(:external_api).wrap do
      # API call that might fail
      external_api.send(message)
    end
  end
end
```

## Monitoring and Alerting

### Queue Size Monitoring

Monitor DLQ growth:

```ruby
# Simple monitoring script
loop do
  dlq = SmartMessage::DeadLetterQueue.default
  size = dlq.size
  
  if size > 100
    send_alert("DLQ size critical: #{size} messages")
  elsif size > 50
    send_warning("DLQ size warning: #{size} messages")
  end
  
  sleep 60  # Check every minute
end
```

### Error Pattern Detection

Detect systematic failures:

```ruby
dlq = SmartMessage::DeadLetterQueue.default
stats = dlq.statistics

# Check for dominant error patterns
top_error = stats[:by_error].max_by { |_, count| count }
if top_error && top_error[1] > 10
  alert("Systematic failure detected: #{top_error[0]} (#{top_error[1]} occurrences)")
end

# Check for specific service failures
stats[:by_class].each do |klass, count|
  if count > 5
    alert("Service degradation: #{klass} has #{count} failures")
  end
end
```

## Best Practices

### 1. Regular Monitoring

Set up monitoring for DLQ size and growth rate:

```ruby
# Prometheus metrics example
dlq_size = Prometheus::Client::Gauge.new(:dlq_size, 'Dead letter queue size')
dlq_size.set(SmartMessage::DeadLetterQueue.default.size)
```

### 2. Automated Replay

Schedule periodic replay attempts:

```ruby
# Sidekiq job example
class ReplayDLQJob
  include Sidekiq::Worker
  
  def perform
    dlq = SmartMessage::DeadLetterQueue.default
    
    # Only replay if queue is manageable
    if dlq.size < 100
      results = dlq.replay_all
      log_results(results)
    else
      # Replay in smaller batches
      results = dlq.replay_batch(10)
      log_results(results)
    end
  end
  
  private
  
  def log_results(results)
    Rails.logger.info("DLQ Replay: #{results[:success]} success, #{results[:failed]} failed")
  end
end
```

### 3. Archival Strategy

Archive old messages:

```ruby
# Archive messages older than 7 days
def archive_old_messages
  dlq = SmartMessage::DeadLetterQueue.default
  archive_path = "/var/archive/dlq_#{Date.today}.jsonl"
  
  seven_days_ago = Time.now - (7 * 86400)
  old_messages = dlq.export_range(Time.at(0), seven_days_ago)
  
  if old_messages.any?
    File.write(archive_path, old_messages.map(&:to_json).join("\n"))
    # Remove archived messages from active DLQ
    # (Note: This would require implementing a remove_range method)
  end
end
```

### 4. Error Classification

Classify errors for better handling:

```ruby
class DLQAnalyzer
  TRANSIENT_ERRORS = [
    /connection refused/i,
    /timeout/i,
    /temporarily unavailable/i
  ]
  
  PERMANENT_ERRORS = [
    /invalid message format/i,
    /unauthorized/i,
    /not found/i
  ]
  
  def self.classify_errors(dlq)
    transient = []
    permanent = []
    
    dlq.inspect_messages(limit: 100).each do |msg|
      if TRANSIENT_ERRORS.any? { |pattern| msg[:error].match?(pattern) }
        transient << msg
      elsif PERMANENT_ERRORS.any? { |pattern| msg[:error].match?(pattern) }
        permanent << msg
      end
    end
    
    { transient: transient, permanent: permanent }
  end
end
```

## Troubleshooting

### Common Issues

#### 1. DLQ File Growing Too Large

```ruby
# Rotate DLQ files
def rotate_dlq
  dlq = SmartMessage::DeadLetterQueue.default
  timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
  
  # Move current file
  FileUtils.mv(dlq.file_path, "#{dlq.file_path}.#{timestamp}")
  
  # DLQ will create new file automatically
end
```

#### 2. Replay Failures

```ruby
# Debug replay failures
result = dlq.replay_one
unless result[:success]
  puts "Replay failed: #{result[:error]}"
  
  # Check if message class still exists
  message = dlq.peek
  begin
    message[:header][:message_class].constantize
  rescue NameError => e
    puts "Message class no longer exists: #{e.message}"
  end
end
```

#### 3. Corrupted DLQ File

```ruby
# Recover from corrupted file
def recover_dlq(corrupted_path)
  recovered = []
  
  File.foreach(corrupted_path) do |line|
    begin
      entry = JSON.parse(line.strip, symbolize_names: true)
      recovered << entry
    rescue JSON::ParserError
      # Skip corrupted line
      puts "Skipping corrupted line: #{line[0..50]}..."
    end
  end
  
  # Write recovered entries to new file
  new_dlq = SmartMessage::DeadLetterQueue.new("#{corrupted_path}.recovered")
  recovered.each do |entry|
    new_dlq.enqueue(
      SmartMessage::Header.new(entry[:header]),
      entry[:payload],
      error: entry[:error],
      retry_count: entry[:retry_count]
    )
  end
  
  puts "Recovered #{recovered.size} messages"
end
```

## Performance Considerations

### File I/O Optimization

The DLQ uses several optimizations:

1. **Append-only writes**: New messages are appended, not inserted
2. **Immediate sync**: `file.fsync` ensures durability
3. **Mutex protection**: Thread-safe but may create contention
4. **Line-based processing**: Memory efficient for large files

### Scaling Strategies

For high-volume systems:

```ruby
# Use multiple DLQ instances by message type
class DLQRouter
  def self.get_dlq_for(message_class)
    case message_class
    when /Payment/
      @payment_dlq ||= SmartMessage::DeadLetterQueue.new('/var/log/payment_dlq.jsonl')
    when /Order/
      @order_dlq ||= SmartMessage::DeadLetterQueue.new('/var/log/order_dlq.jsonl')
    else
      SmartMessage::DeadLetterQueue.default
    end
  end
end
```

### Memory Usage

For large DLQ files:

```ruby
# Process in chunks to avoid memory issues
def process_large_dlq(dlq, chunk_size: 100)
  processed = 0
  
  while dlq.size > 0 && processed < 1000
    # Process only chunk_size at a time
    chunk_size.times do
      break if dlq.size == 0
      
      message = dlq.dequeue
      process_message(message)
      processed += 1
    end
    
    # Let other operations run
    sleep(0.1)
  end
  
  processed
end
```

## Security Considerations

### File Permissions

Ensure proper file permissions:

```ruby
# Set restrictive permissions on DLQ files
def secure_dlq_file(path)
  File.chmod(0600, path) if File.exist?(path)  # Read/write for owner only
end
```

### Sensitive Data

Be careful with sensitive data in DLQ:

```ruby
# Sanitize sensitive data before storing
def sanitize_for_dlq(payload)
  data = JSON.parse(payload)
  data['credit_card'] = 'REDACTED' if data['credit_card']
  data['password'] = 'REDACTED' if data['password']
  data.to_json
end
```

### Encryption

For sensitive environments:

```ruby
# Example: Encrypt DLQ entries
require 'openssl'

class EncryptedDLQ < SmartMessage::DeadLetterQueue
  def enqueue(header, payload, **options)
    encrypted_payload = encrypt(payload)
    super(header, encrypted_payload, **options)
  end
  
  def dequeue
    entry = super
    return nil unless entry
    
    entry[:payload] = decrypt(entry[:payload])
    entry
  end
  
  private
  
  def encrypt(data)
    # Implement encryption
  end
  
  def decrypt(data)
    # Implement decryption
  end
end
```

## Summary

The SmartMessage Dead Letter Queue provides:

- **Reliability**: Automatic capture of failed messages
- **Flexibility**: Multiple configuration options
- **Recoverability**: Comprehensive replay capabilities
- **Observability**: Statistics and filtering for analysis
- **Integration**: Seamless circuit breaker integration
- **Production-Ready**: Thread-safe, performant, and scalable

The DLQ ensures that no message is lost, even during system failures, and provides the tools needed to analyze, replay, and manage failed messages effectively.