# Message Deduplication

SmartMessage provides a comprehensive message deduplication system using Deduplication Queues (DDQ) to prevent duplicate processing of messages with the same UUID. The system is designed with handler-scoped isolation, ensuring that different message handlers maintain independent deduplication state.

## Overview

Message deduplication in SmartMessage works by:

1. **Handler-Scoped Tracking**: Each message handler (subscription) gets its own DDQ instance
2. **UUID-Based Detection**: Message UUIDs are tracked in circular buffers for O(1) lookup performance
3. **Configurable Storage**: Support for both memory-based and Redis-based storage backends
4. **Automatic Integration**: Seamlessly integrates with the existing dispatcher and subscription system

## Architecture

### Handler-Only Scoping

The key innovation in SmartMessage's deduplication system is **handler-only scoping**. DDQ keys are automatically derived from the combination of message class and handler method:

```
DDQ Key Format: "MessageClass:HandlerMethod"
```

Examples:
- `"OrderMessage:PaymentService.process"`
- `"OrderMessage:FulfillmentService.handle"`
- `"InvoiceMessage:PaymentService.process"`

This design provides:
- **Natural Isolation**: Each handler has its own deduplication context
- **Cross-Process Support**: Same handler across different processes gets isolated DDQs
- **No Parameter Pollution**: No need for explicit subscriber identification in the API

### DDQ Data Structure

Each DDQ uses a hybrid data structure for optimal performance:

```ruby
# Hybrid Array + Set Design
@circular_array = Array.new(size)  # Maintains insertion order for eviction
@lookup_set = Set.new              # Provides O(1) UUID lookup
@index = 0                         # Current insertion position
```

Benefits:
- **O(1) Lookup**: Set provides constant-time duplicate detection
- **O(1) Insertion**: Array provides constant-time insertion and eviction
- **Memory Bounded**: Circular buffer automatically evicts oldest entries
- **Thread Safe**: Mutex protection for concurrent access

## Configuration

### Basic Setup

Enable deduplication for a message class:

```ruby
class OrderMessage < SmartMessage::Base
  version 1
  property :order_id, required: true
  property :amount, required: true
  
  # Configure deduplication
  ddq_size 100              # Track last 100 UUIDs (default: 100)
  ddq_storage :memory       # Storage backend (default: :memory)
  enable_deduplication!     # Enable DDQ for this message class
  
  def self.process(message)
    puts "Processing order: #{message.order_id}"
  end
end
```

### Storage Backends

#### Memory Storage

Best for single-process applications:

```ruby
class LocalMessage < SmartMessage::Base
  ddq_size 50
  ddq_storage :memory
  enable_deduplication!
end
```

Memory Usage (approximate):
- 10 UUIDs: ~480 bytes
- 100 UUIDs: ~4.8 KB  
- 1000 UUIDs: ~48 KB

#### Redis Storage

Best for distributed/multi-process applications:

```ruby
class DistributedMessage < SmartMessage::Base
  ddq_size 1000
  ddq_storage :redis, 
    redis_url: 'redis://localhost:6379',
    redis_db: 1,
    key_prefix: 'ddq'
  enable_deduplication!
end
```

Redis DDQ features:
- **Distributed State**: Shared across multiple processes
- **Persistence**: Survives process restarts
- **TTL Support**: Automatic expiration of old entries
- **Atomic Operations**: Transaction safety for concurrent access

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ddq_size` | Integer | 100 | Maximum UUIDs to track in circular buffer |
| `ddq_storage` | Symbol | `:memory` | Storage backend (`:memory` or `:redis`) |
| `redis_url` | String | `'redis://localhost:6379'` | Redis connection URL |
| `redis_db` | Integer | 0 | Redis database number |
| `key_prefix` | String | `'ddq'` | Prefix for Redis keys |
| `ttl` | Integer | 3600 | TTL for Redis entries (seconds) |

## Usage Examples

### Multiple Handlers per Message Class

```ruby
class OrderMessage < SmartMessage::Base
  ddq_size 200
  ddq_storage :memory
  enable_deduplication!
end

# Each gets separate DDQ tracking
OrderMessage.subscribe('PaymentService.process')      # DDQ: "OrderMessage:PaymentService.process"
OrderMessage.subscribe('FulfillmentService.handle')   # DDQ: "OrderMessage:FulfillmentService.handle"
OrderMessage.subscribe('AuditService.log_order')      # DDQ: "OrderMessage:AuditService.log_order"

# Same UUID can be processed by each handler independently
order = OrderMessage.new(order_id: "12345", amount: 99.99)
order.publish  # All three handlers will process this message
```

### Cross-Message-Class Handlers

```ruby
class PaymentService
  def self.process(message)
    puts "PaymentService processing: #{message.class.name}"
  end
end

# Same handler, different message classes = separate DDQs
OrderMessage.subscribe('PaymentService.process')     # DDQ: "OrderMessage:PaymentService.process"
InvoiceMessage.subscribe('PaymentService.process')   # DDQ: "InvoiceMessage:PaymentService.process"
RefundMessage.subscribe('PaymentService.process')    # DDQ: "RefundMessage:PaymentService.process"
```

### Distributed Processing

```ruby
# Process A (payment-service-1)
class OrderMessage < SmartMessage::Base
  ddq_storage :redis, redis_url: 'redis://shared-redis:6379'
  enable_deduplication!
end

OrderMessage.subscribe('PaymentService.process')

# Process B (payment-service-2)  
# Same configuration, same handler = shared DDQ in Redis
OrderMessage.subscribe('PaymentService.process')

# Only one process will handle each unique UUID
```

## API Reference

### Class Methods

#### `ddq_size(size)`
Configure the maximum number of UUIDs to track:
```ruby
OrderMessage.ddq_size(500)  # Track last 500 UUIDs
```

#### `ddq_storage(storage, **options)`
Configure the storage backend:
```ruby
OrderMessage.ddq_storage(:memory)
OrderMessage.ddq_storage(:redis, redis_url: 'redis://localhost:6379', redis_db: 2)
```

#### `enable_deduplication!`
Enable deduplication for the message class:
```ruby
OrderMessage.enable_deduplication!
```

#### `disable_deduplication!`
Disable deduplication for the message class:
```ruby
OrderMessage.disable_deduplication!
```

#### `ddq_enabled?`
Check if deduplication is enabled:
```ruby
puts OrderMessage.ddq_enabled?  # => true/false
```

#### `ddq_config`
Get current DDQ configuration:
```ruby
config = OrderMessage.ddq_config
# => {enabled: true, size: 100, storage: :memory, options: {}}
```

#### `ddq_stats`
Get DDQ statistics for all handlers:
```ruby
stats = OrderMessage.ddq_stats
# => {enabled: true, current_count: 45, utilization: 45.0, ...}
```

#### `clear_ddq!`
Clear all DDQ instances for the message class:
```ruby
OrderMessage.clear_ddq!
```

#### `duplicate_uuid?(uuid)`
Check if a UUID is tracked as duplicate:
```ruby
is_dup = OrderMessage.duplicate_uuid?("some-uuid-123")  # => true/false
```

### Instance Methods

#### `duplicate?`
Check if this message instance is a duplicate:
```ruby
message = OrderMessage.new(order_id: "123", amount: 99.99)
puts message.duplicate?  # => true/false
```

#### `mark_as_processed!`
Manually mark this message as processed:
```ruby
message.mark_as_processed!  # Adds UUID to DDQ
```

## Integration with Dispatcher

The deduplication system integrates seamlessly with SmartMessage's dispatcher:

### Message Flow with DDQ

1. **Message Receipt**: Dispatcher receives decoded message
2. **Handler Iteration**: For each subscribed handler:
   - **DDQ Check**: Check handler's DDQ for message UUID
   - **Skip Duplicates**: If UUID found, log and skip to next handler
   - **Process New**: If UUID not found, route to handler
   - **Mark Processed**: After successful processing, add UUID to handler's DDQ

### Logging

The dispatcher provides detailed logging for deduplication events:

```
[INFO] [SmartMessage::Dispatcher] Skipping duplicate for PaymentService.process: uuid-123
[DEBUG] [SmartMessage::Dispatcher] Marked UUID as processed for FulfillmentService.handle: uuid-456
```

### Statistics Integration

DDQ statistics are integrated with SmartMessage's built-in statistics system:

```ruby
# Access via dispatcher
dispatcher = SmartMessage::Dispatcher.new
ddq_stats = dispatcher.ddq_stats

# Example output:
# {
#   "OrderMessage:PaymentService.process" => {
#     size: 100, current_count: 23, utilization: 23.0, 
#     storage_type: :memory, implementation: "SmartMessage::DDQ::Memory"
#   },
#   "OrderMessage:FulfillmentService.handle" => { ... }
# }
```

## Performance Characteristics

### Memory DDQ Performance

- **Lookup Time**: O(1) - Set provides constant-time contains check
- **Insertion Time**: O(1) - Array provides constant-time insertion
- **Memory Usage**: ~48 bytes per UUID (including Set and Array overhead)
- **Thread Safety**: Mutex-protected for concurrent access

### Redis DDQ Performance

- **Lookup Time**: O(1) - Redis SET provides constant-time membership test
- **Insertion Time**: O(1) - Redis LPUSH + LTRIM for circular behavior
- **Network Overhead**: 1-2 Redis commands per duplicate check
- **Persistence**: Automatic persistence and cross-process sharing

### Benchmarks

Memory DDQ (1000 entries):
- **Memory Usage**: ~57 KB
- **Lookup Performance**: 0.001ms average
- **Insertion Performance**: 0.002ms average

Redis DDQ (1000 entries):
- **Memory Usage**: Stored in Redis
- **Lookup Performance**: 0.5-2ms average (network dependent)
- **Insertion Performance**: 1-3ms average (network dependent)

## Best Practices

### 1. Choose Appropriate DDQ Size

Size DDQ based on your message volume and acceptable duplicate window:

```ruby
# High-volume service: larger DDQ
class HighVolumeMessage < SmartMessage::Base
  ddq_size 10000  # Track last 10k messages
  ddq_storage :redis
  enable_deduplication!
end

# Low-volume service: smaller DDQ
class LowVolumeMessage < SmartMessage::Base
  ddq_size 50     # Track last 50 messages  
  ddq_storage :memory
  enable_deduplication!
end
```

### 2. Use Redis for Distributed Systems

For multi-process deployments, always use Redis storage:

```ruby
class DistributedMessage < SmartMessage::Base
  ddq_storage :redis, 
    redis_url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'),
    redis_db: ENV.fetch('DDQ_REDIS_DB', 1).to_i
  enable_deduplication!
end
```

### 3. Monitor DDQ Statistics

Regularly monitor DDQ utilization:

```ruby
# In monitoring/health check code
stats = OrderMessage.ddq_stats
if stats[:utilization] > 90
  logger.warn "DDQ utilization high: #{stats[:utilization]}%"
end
```

### 4. Handle DDQ Errors Gracefully

The system is designed to fail-open (process messages when DDQ fails):

```ruby
# DDQ failures are logged but don't prevent message processing
# Monitor logs for DDQ-related errors:
# [ERROR] [SmartMessage::DDQ] Failed to check duplicate: Redis connection error
```

## Troubleshooting

### Common Issues

#### 1. Messages Not Being Deduplicated

**Symptoms**: Same UUID processed multiple times by same handler
**Causes**:
- Deduplication not enabled: `enable_deduplication!` missing
- Different handlers: Each handler has separate DDQ
- DDQ size too small: Old UUIDs evicted too quickly

**Solutions**:
```ruby
# Verify deduplication is enabled
puts OrderMessage.ddq_enabled?  # Should be true

# Check DDQ configuration
puts OrderMessage.ddq_config

# Increase DDQ size if needed
OrderMessage.ddq_size(1000)
```

#### 2. Redis Connection Errors

**Symptoms**: DDQ errors in logs, messages still processing
**Causes**: Redis connectivity issues

**Solutions**:
```ruby
# Verify Redis connection
redis_config = OrderMessage.ddq_config[:options]
puts "Redis URL: #{redis_config[:redis_url]}"

# Test Redis connectivity
require 'redis'
redis = Redis.new(url: redis_config[:redis_url])
puts redis.ping  # Should return "PONG"
```

#### 3. High Memory Usage

**Symptoms**: Increasing memory usage in memory DDQ
**Causes**: DDQ size too large for available memory

**Solutions**:
```ruby
# Check memory usage
stats = OrderMessage.ddq_stats
puts "Memory usage: #{stats[:current_count] * 48} bytes"

# Reduce DDQ size
OrderMessage.ddq_size(100)  # Smaller size

# Or switch to Redis
OrderMessage.ddq_storage(:redis)
```

### Debugging DDQ Issues

```ruby
# Enable debug logging
SmartMessage.configure do |config|
  config.log_level = :debug
end

# Check specific UUID
uuid = "test-uuid-123" 
puts "Is duplicate: #{OrderMessage.duplicate_uuid?(uuid)}"

# Clear DDQ for testing
OrderMessage.clear_ddq!

# Monitor DDQ stats
stats = OrderMessage.ddq_stats
puts "Current count: #{stats[:current_count]}"
puts "Utilization: #{stats[:utilization]}%"
```

## Migration Guide

### From Class-Level to Handler-Level DDQ

If upgrading from a previous version with class-level deduplication:

**Before (hypothetical)**:
```ruby
# All handlers shared one DDQ per message class
OrderMessage.subscribe('PaymentService.process')
OrderMessage.subscribe('FulfillmentService.handle')
# Both shared the same DDQ
```

**After (current)**:
```ruby
# Each handler gets its own DDQ automatically
OrderMessage.subscribe('PaymentService.process')     # DDQ: "OrderMessage:PaymentService.process"
OrderMessage.subscribe('FulfillmentService.handle')  # DDQ: "OrderMessage:FulfillmentService.handle"
# Separate DDQs with isolated tracking
```

**Benefits of Migration**:
- **Better Isolation**: Handler failures don't affect other handlers' deduplication
- **Flexible Filtering**: Different handlers can have different subscription filters
- **Cross-Process Safety**: Handlers with same name across processes get separate DDQs

The migration is automatic - no code changes required. The new system provides better isolation and reliability.