# Redis Transport

The **Redis Transport** is the foundational Redis-based transport implementation for SmartMessage. It uses Redis pub/sub channels for message distribution and provides reliable, high-performance messaging with minimal setup.

## Overview

Redis Transport is perfect for:
- **Simple pub/sub scenarios** - Basic message broadcasting
- **Development and testing** - Quick Redis-based messaging
- **Legacy compatibility** - Original SmartMessage Redis implementation
- **High performance** - Direct Redis pub/sub with minimal overhead

## Key Features

- 🚀 **Direct Redis Pub/Sub** - Uses native Redis PUBLISH/SUBSCRIBE
- ⚡ **High Performance** - ~1ms latency, 80K+ messages/second
- 🔄 **Auto-Reconnection** - Automatic Redis connection recovery
- 🧵 **Thread-Based Subscribers** - Traditional thread-per-subscriber model
- 🏷️ **Simple Channel Names** - Uses message class name as channel
- 📡 **Broadcast Delivery** - All subscribers receive all messages

## Architecture

```
Publisher → Redis Channel → All Subscribers
         (class name)     (thread-based)
```

The Redis Transport uses the message class name directly as the Redis channel name. For example, `OrderMessage` publishes to the `OrderMessage` channel.

## Configuration

### Basic Setup

```ruby
# Minimal configuration
transport = SmartMessage::Transport::RedisTransport.new

# With Redis URL
transport = SmartMessage::Transport::RedisTransport.new(
  url: 'redis://localhost:6379'
)

# Full configuration
transport = SmartMessage::Transport::RedisTransport.new(
  url: 'redis://redis.example.com:6379',
  db: 1,
  auto_subscribe: true,
  reconnect_attempts: 5,
  reconnect_delay: 2
)
```

### Using with SmartMessage

```ruby
# Configure as default transport
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::RedisTransport.new(
    url: ENV['REDIS_URL'] || 'redis://localhost:6379'
  )
end

# Use in message class
class OrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :customer_email, required: true
  
  transport :redis
  
  def process
    puts "Processing order: #{order_id} for #{customer_email}"
    # Business logic here
  end
end
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | `redis://localhost:6379` | Redis connection URL |
| `db` | Integer | `0` | Redis database number |
| `auto_subscribe` | Boolean | `true` | Automatically start subscriber thread |
| `reconnect_attempts` | Integer | `5` | Number of reconnection attempts |
| `reconnect_delay` | Integer | `1` | Seconds between reconnection attempts |

## Usage Examples

### Basic Message Processing

```ruby
# Define message
class UserNotification < SmartMessage::Base
  property :user_id, required: true
  property :message, required: true
  property :type, default: 'info'
  
  def process
    user = User.find(user_id)
    user.notifications.create!(
      message: message,
      type: type
    )
    puts "Notification sent to user #{user_id}: #{message}"
  end
end

# Publish notification
UserNotification.new(
  user_id: 123,
  message: "Your order has been shipped!",
  type: "success"
).publish

# Output: Notification sent to user 123: Your order has been shipped!
```

### Multiple Publishers and Subscribers

```ruby
# Publisher 1 (Web Application)
class OrderCreated < SmartMessage::Base
  property :order_id, required: true
  property :user_id, required: true
  property :total, required: true
  
  def process
    # This runs on all subscribers
    puts "Order #{order_id} created for user #{user_id}: $#{total}"
  end
end

# Publisher 2 (Admin Panel)
class OrderCancelled < SmartMessage::Base
  property :order_id, required: true
  property :reason, required: true
  
  def process
    puts "Order #{order_id} cancelled: #{reason}"
  end
end

# Both services will receive both message types
# All subscribers get all messages - broadcast behavior

# Publish from web app
OrderCreated.new(
  order_id: "ORD-001", 
  user_id: 456, 
  total: 99.99
).publish

# Publish from admin panel
OrderCancelled.new(
  order_id: "ORD-002", 
  reason: "Customer request"
).publish
```

### Connection Management

```ruby
# Check connection status
transport = SmartMessage::Transport::RedisTransport.new
puts "Connected: #{transport.connected?}"

# Manual connection control
transport.stop_subscriber
transport.start_subscriber

# Access Redis connections directly
pub_redis = transport.redis_pub
sub_redis = transport.redis_sub

# Test connection
begin
  pub_redis.ping
  puts "Redis connection healthy"
rescue Redis::ConnectionError
  puts "Redis connection failed"
end
```

### Error Handling

```ruby
class ReliableMessage < SmartMessage::Base
  property :data, required: true
  
  def process
    begin
      # Potentially failing operation
      external_api_call(data)
    rescue => e
      logger.error "Failed to process message: #{e.message}"
      # Message processing failed, but won't retry
      # Use dead letter queue for failed messages
    end
  end
  
  private
  
  def external_api_call(data)
    # Simulate external API call
    raise "API unavailable" if rand < 0.1
    puts "Processed: #{data}"
  end
end

# Publish messages - some may fail processing
10.times do |i|
  ReliableMessage.new(data: "item-#{i}").publish
end
```

## Performance Characteristics

- **Latency**: ~1ms average message delivery
- **Throughput**: 80,000+ messages/second
- **Memory per Subscriber**: ~1MB baseline
- **Concurrent Subscribers**: ~200 practical limit
- **Connection Overhead**: 2 Redis connections (pub + sub)
- **Message Persistence**: None (fire-and-forget)
- **Message Ordering**: No guarantees

## API Reference

### Instance Methods

#### `#connected?`
Checks if Redis connections are healthy.

```ruby
if transport.connected?
  puts "Redis transport ready"
else
  puts "Redis transport offline"
end
```

#### `#start_subscriber`
Manually starts the subscriber thread (if `auto_subscribe: false`).

```ruby
transport = SmartMessage::Transport::RedisTransport.new(auto_subscribe: false)
# ... do setup ...
transport.start_subscriber
```

#### `#stop_subscriber`
Stops the subscriber thread gracefully.

```ruby
transport.stop_subscriber
puts "Subscriber stopped"
```

#### `#subscriber_running?`
Checks if the subscriber thread is active.

```ruby
if transport.subscriber_running?
  puts "Actively listening for messages"
end
```

## Channel Naming

Redis Transport uses simple channel naming:
- **Message Class**: `OrderMessage`
- **Redis Channel**: `"OrderMessage"`
- **Subscription**: Exact channel name match

```ruby
# These all use the "UserMessage" channel
class UserMessage < SmartMessage::Base
  property :user_id
end

# Publishing
UserMessage.new(user_id: 123).publish
# → Publishes to Redis channel "UserMessage"

# Subscribing  
UserMessage.subscribe
# → Subscribes to Redis channel "UserMessage"
```

## Use Cases

### Simple Applications

```ruby
# Perfect for straightforward pub/sub needs
class SystemAlert < SmartMessage::Base
  property :level, required: true
  property :message, required: true
  
  def process
    case level
    when 'critical'
      send_pager_alert(message)
    when 'warning'  
      log_warning(message)
    else
      log_info(message)
    end
  end
end

SystemAlert.new(level: 'critical', message: 'Database offline').publish
```

### Development Environment

```ruby
# config/environments/development.rb
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport::RedisTransport.new(
    url: 'redis://localhost:6379',
    db: 1  # Separate dev database
  )
  config.logger.level = Logger::DEBUG
end
```

### Legacy System Integration

```ruby
# Maintaining compatibility with existing Redis pub/sub systems
class LegacyEvent < SmartMessage::Base
  property :event_type, required: true
  property :payload, required: true
  
  def process
    # Process in SmartMessage format
    LegacyEventProcessor.new(event_type, payload).process
  end
end

# External systems can still publish to "LegacyEvent" channel
# SmartMessage will automatically process them
```

## Performance Tuning

### Connection Pooling

```ruby
# For high-throughput applications, consider connection pooling
require 'connection_pool'

redis_pool = ConnectionPool.new(size: 10) do
  Redis.new(url: 'redis://localhost:6379')
end

# Use custom Redis instance
transport = SmartMessage::Transport::RedisTransport.new
transport.instance_variable_set(:@redis_pub, redis_pool.with { |r| r })
```

### Monitoring

```ruby
# Monitor Redis transport health
class HealthCheck
  def self.redis_transport_status
    transport = SmartMessage.configuration.default_transport
    {
      connected: transport.connected?,
      subscriber_running: transport.subscriber_running?,
      redis_info: transport.redis_pub.info
    }
  end
end

puts HealthCheck.redis_transport_status
```

## Best Practices

### Configuration
- Use environment variables for Redis URLs
- Set appropriate database numbers for different environments
- Configure reasonable reconnection settings

### Error Handling
- Implement proper error handling in message processing
- Use logging to track message failures
- Consider implementing dead letter queue pattern

### Monitoring
- Monitor Redis connection health
- Track message throughput and processing times
- Set up alerts for subscriber thread failures

### Testing
- Use separate Redis databases for testing
- Clear Redis data between tests
- Mock Redis for unit tests

## Limitations

### No Pattern Matching
Redis Transport requires exact channel name matches:

```ruby
# This works - exact match
OrderMessage.subscribe  # Subscribes to "OrderMessage"

# This doesn't work - no wildcard support
# Can't subscribe to "Order*" or "*Message"
```

### No Message Persistence
Messages are lost if no subscribers are listening:

```ruby
# If no subscribers are running, this message is lost
OrderMessage.new(order_id: 'ORD-001').publish
```

### Broadcasting Only
All subscribers receive all messages:

```ruby
# If 3 services subscribe to OrderMessage,
# all 3 will process every OrderMessage
# No load balancing between subscribers
```


## Examples

The `examples/redis/` directory contains production-ready examples demonstrating Redis Transport capabilities:

### IoT and Real-Time Messaging
- **[01_smart_home_iot_demo.rb](https://github.com/MadBomber/smart_message/blob/main/examples/redis/01_smart_home_iot_demo.rb)** - Complete smart home IoT system with Redis pub/sub
  - Real-time sensor data publishing (temperature, motion, battery levels)
  - Device command routing with prefix-based filtering
  - Alert generation and dashboard monitoring
  - Multi-process distributed architecture

### Key Features Demonstrated

The IoT example showcases all Redis Transport capabilities:
- **Direct Redis Pub/Sub** - High-performance message broadcasting
- **Channel-Based Routing** - Each message type uses dedicated channels
- **Device-Specific Filtering** - Commands routed by device ID prefixes
- **Real-Time Data Flow** - Continuous sensor data streaming
- **Multi-Process Communication** - Distributed system simulation

### Running Examples

```bash
# Prerequisites: Start Redis server
redis-server

# Navigate to the SmartMessage directory
cd smart_message

# Run the Redis Transport IoT demo
ruby examples/redis/01_smart_home_iot_demo.rb

# Monitor Redis channels during the demo
redis-cli MONITOR
```

### Example Architecture

The IoT demo creates a complete distributed system:
- **5 IoT processes** - Sensors publishing data every 3-5 seconds
- **Dashboard process** - Aggregating and displaying system status
- **Redis channels** - `SensorDataMessage`, `DeviceCommandMessage`, `AlertMessage`
- **Device filtering** - THERM-, CAM-, LOCK- prefix routing

Each example includes comprehensive logging and demonstrates production-ready patterns for Redis-based messaging systems.

### Additional Resources

For more Redis Transport examples and patterns, also see:
- **[Memory Transport Examples](https://github.com/MadBomber/smart_message/tree/main/examples/memory)** - Can be adapted to Redis Transport by changing configuration
- **[Complete Documentation](https://github.com/MadBomber/smart_message/blob/main/examples/redis/smart_home_iot_dataflow.md)** - Detailed data flow analysis with SVG diagrams

## Related Documentation

- [Transport Overview](../reference/transports.md) - All available transports
- [Examples & Use Cases](../getting-started/examples.md) - Practical usage patterns
- [Architecture Overview](../core-concepts/architecture.md) - How SmartMessage works