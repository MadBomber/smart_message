# Transport Layer

The transport layer is responsible for moving messages between systems. SmartMessage provides a pluggable transport architecture that supports various backend systems.

## Overview

Transports handle:
- **Publishing**: Sending messages to a destination
- **Subscribing**: Registering interest in message types
- **Routing**: Directing incoming messages to the dispatcher
- **Connection Management**: Handling connections to external systems

## Built-in Transports

### STDOUT Transport

Perfect for development, debugging, and logging scenarios.

**Features:**
- Outputs messages to console or file
- Optional loopback for testing subscriptions
- Human-readable message formatting
- No external dependencies

**Usage:**

```ruby
# Basic STDOUT output
transport = SmartMessage::Transport.create(:stdout)

# With loopback enabled (messages get processed locally)
transport = SmartMessage::Transport.create(:stdout, loopback: true)

# Output to file instead of console
transport = SmartMessage::Transport.create(:stdout, output: "messages.log")

# Configure in message class
class LogMessage < SmartMessage::Base
  property :level
  property :message
  
  config do
    transport SmartMessage::Transport.create(:stdout, 
      output: "app.log",
      loopback: false
    )
  end
end
```

**Options:**
- `loopback` (Boolean): Whether to process published messages locally (default: false)
- `output` (String|IO): Output destination - filename string or IO object (default: $stdout)

**Example Output:**
```
===================================================
== SmartMessage Published via STDOUT Transport
== Header: #<SmartMessage::Header:0x... @uuid="abc-123", @message_class="MyMessage", ...>
== Payload: {"user_id":123,"action":"login","timestamp":"2025-08-17T10:30:00Z"}
===================================================
```

### Memory Transport

Ideal for testing and in-memory message queuing.

**Features:**
- Stores messages in memory
- Thread-safe operations
- Optional auto-processing
- Message inspection capabilities
- Memory overflow protection

**Usage:**

```ruby
# Auto-process messages as they're published
transport = SmartMessage::Transport.create(:memory, auto_process: true)

# Store messages without processing (manual control)
transport = SmartMessage::Transport.create(:memory, auto_process: false)

# Configure maximum message storage
transport = SmartMessage::Transport.create(:memory, 
  auto_process: false,
  max_messages: 500
)

# Use in message class
class TestMessage < SmartMessage::Base
  property :data
  
  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
  end
end
```

**Options:**
- `auto_process` (Boolean): Automatically route messages to dispatcher (default: true)
- `max_messages` (Integer): Maximum messages to store in memory (default: 1000)

**Message Management:**

```ruby
transport = SmartMessage::Transport.create(:memory)

# Check stored messages
puts transport.message_count
puts transport.all_messages

# Process all pending messages manually
transport.process_all

# Clear all stored messages
transport.clear_messages

# Access individual messages
messages = transport.all_messages
messages.each do |msg|
  puts "Published at: #{msg[:published_at]}"
  puts "Header: #{msg[:header]}"
  puts "Payload: #{msg[:payload]}"
end
```

### Redis Transport

Production-ready Redis pub/sub transport for distributed messaging.

**Features:**
- Redis pub/sub messaging
- Automatic channel management using message class names
- Thread-safe subscriber management
- Connection resilience with automatic reconnection
- Configurable connection parameters
- Background message subscription threads

**Usage:**

```ruby
# Basic Redis configuration
transport = SmartMessage::Transport.create(:redis, 
  url: 'redis://localhost:6379',
  db: 0
)

# Production configuration with custom options
transport = SmartMessage::Transport.create(:redis,
  url: 'redis://prod-redis:6379',
  db: 1,
  auto_subscribe: true,
  reconnect_attempts: 5,
  reconnect_delay: 2
)

# Configure in message class
class OrderMessage < SmartMessage::Base
  property :order_id
  property :customer_id
  property :amount
  
  config do
    transport SmartMessage::Transport.create(:redis, 
      url: 'redis://localhost:6379',
      db: 1
    )
    serializer SmartMessage::Serializer::Json.new
  end
  
  def self.process(decoded_message)
    # decoded_message is already a message instance
    order = decoded_message
    puts "Processing order #{order.order_id} for $#{order.amount}"
    # Your business logic here
  end
end

# Subscribe to messages (creates Redis subscription to "OrderMessage" channel)
OrderMessage.subscribe

# Publish messages (publishes to "OrderMessage" Redis channel)
order = OrderMessage.new(
  order_id: "ORD-123",
  customer_id: "CUST-456", 
  amount: 99.99
)
order.publish
```

**Options:**
- `url` (String): Redis connection URL (default: 'redis://localhost:6379')
- `db` (Integer): Redis database number (default: 0)
- `auto_subscribe` (Boolean): Automatically start subscriber thread (default: true)
- `reconnect_attempts` (Integer): Number of reconnection attempts (default: 5)
- `reconnect_delay` (Integer): Delay between reconnection attempts in seconds (default: 1)
- `debug` (Boolean): Enable debug output (default: false)

**Channel Naming:**

The Redis transport uses the message class name as the Redis channel name. This provides automatic routing:

```ruby
class UserMessage < SmartMessage::Base
  # Messages published to/from Redis channel "UserMessage"
end

class AdminMessage < SmartMessage::Base  
  # Messages published to/from Redis channel "AdminMessage"
end

class OrderProcessing::PaymentMessage < SmartMessage::Base
  # Messages published to/from Redis channel "OrderProcessing::PaymentMessage"
end
```

**Connection Management:**

```ruby
transport = SmartMessage::Transport.create(:redis, url: 'redis://localhost:6379')

# Check connection status
puts transport.connected?  # => true/false

# Manual connection management
transport.connect
transport.disconnect

# The transport automatically reconnects on connection failures
```

**Multi-Message Type Support:**

```ruby
# Different message types can share the same Redis transport
redis_transport = SmartMessage::Transport.create(:redis, 
  url: 'redis://localhost:6379',
  auto_subscribe: true
)

# Configure multiple message classes to use the same transport
[OrderMessage, PaymentMessage, ShippingMessage].each do |msg_class|
  msg_class.config do
    transport redis_transport
    serializer SmartMessage::Serializer::Json.new
  end
  
  # Subscribe to each message type (creates separate Redis subscriptions)
  msg_class.subscribe
end

# Publishing to any message type routes to its specific Redis channel
OrderMessage.new(order_id: "123").publish      # -> "OrderMessage" channel
PaymentMessage.new(amount: 50.0).publish       # -> "PaymentMessage" channel
ShippingMessage.new(tracking: "ABC").publish   # -> "ShippingMessage" channel
```

**Error Handling and Resilience:**

The Redis transport includes built-in error handling:

```ruby
# Automatic reconnection on connection failures
transport = SmartMessage::Transport.create(:redis,
  url: 'redis://localhost:6379',
  reconnect_attempts: 5,    # Try 5 times to reconnect
  reconnect_delay: 2        # Wait 2 seconds between attempts
)

# Connection failures during publishing will trigger automatic retry
# If all reconnection attempts fail, the original error is raised
```

**Production Deployment:**

```ruby
# Production Redis configuration
class ProductionMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:redis,
      url: ENV['REDIS_URL'] || 'redis://localhost:6379',
      db: ENV['REDIS_DB']&.to_i || 0,
      auto_subscribe: true,
      reconnect_attempts: 10,
      reconnect_delay: 5
    )
    serializer SmartMessage::Serializer::Json.new
    logger Logger.new(STDOUT)
  end
end
```

**Testing with Redis:**

```ruby
# Test configuration (using separate Redis database)
class TestMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:redis,
      url: 'redis://localhost:6379',
      db: 15,  # Use separate database for tests
      auto_subscribe: true
    )
    serializer SmartMessage::Serializer::Json.new
  end
end

# In your test setup
def setup
  # Clear test database
  Redis.new(url: 'redis://localhost:6379', db: 15).flushdb
end
```

## Transport Interface

All transports must implement the `SmartMessage::Transport::Base` interface:

### Required Methods

```ruby
class CustomTransport < SmartMessage::Transport::Base
  # Publish a message
  def publish(message_header, message_payload)
    # Send the message via your transport mechanism
  end
  
  # Optional: Override default options
  def default_options
    {
      connection_timeout: 30,
      retry_attempts: 3
    }
  end
  
  # Optional: Custom configuration setup
  def configure
    @connection = establish_connection(@options)
  end
  
  # Optional: Connection status checking
  def connected?
    @connection&.connected?
  end
  
  # Optional: Cleanup resources
  def disconnect
    @connection&.close
  end
end
```

### Inherited Methods

Transports automatically inherit these methods from `SmartMessage::Transport::Base`:

```ruby
# Subscription management (uses dispatcher)
transport.subscribe(message_class, process_method)
transport.unsubscribe(message_class, process_method) 
transport.unsubscribe!(message_class)
transport.subscribers

# Connection management
transport.connect
transport.disconnect
transport.connected?

# Message receiving (call this from your transport)
transport.receive(message_header, message_payload)  # protected method
```

## Transport Registration

Register custom transports for easy creation:

```ruby
# Register custom transport classes
SmartMessage::Transport.register(:kafka, KafkaTransport)
SmartMessage::Transport.register(:webhook, WebhookTransport)

# List all registered transports (includes built-ins)
puts SmartMessage::Transport.available
# => [:stdout, :memory, :redis, :kafka, :webhook]

# Create instances of built-in transports
redis_transport = SmartMessage::Transport.create(:redis, 
  url: "redis://localhost:6379"
)

memory_transport = SmartMessage::Transport.create(:memory,
  auto_process: true
)

# Create instances of custom transports
kafka_transport = SmartMessage::Transport.create(:kafka,
  servers: ["localhost:9092"]
)
```

## Configuration Patterns

### Class-Level Configuration

```ruby
class OrderMessage < SmartMessage::Base
  property :order_id
  property :amount
  
  # All instances use this transport by default
  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::Json.new
  end
end
```

### Instance-Level Override

```ruby
# Override transport for specific instances
order = OrderMessage.new(order_id: "123", amount: 99.99)

order.config do
  # This instance will use STDOUT instead of memory
  transport SmartMessage::Transport.create(:stdout, loopback: true)
end

order.publish  # Uses STDOUT transport
```

### Runtime Transport Switching

```ruby
class NotificationMessage < SmartMessage::Base
  property :recipient
  property :message
  
  def self.send_via_email
    config do
      transport EmailTransport.new
    end
  end
  
  def self.send_via_sms  
    config do
      transport SMSTransport.new
    end
  end
end

# Switch transport at runtime
NotificationMessage.send_via_email
notification = NotificationMessage.new(
  recipient: "user@example.com",
  message: "Hello!"
)
notification.publish  # Sent via email
```

## Transport Options

### Common Options Pattern

Most transports support these common option patterns:

```ruby
transport = SmartMessage::Transport.create(:custom,
  # Connection options
  host: "localhost",
  port: 5672,
  username: "guest",
  password: "guest",
  
  # Retry options
  retry_attempts: 3,
  retry_delay: 1.0,
  
  # Timeout options
  connection_timeout: 30,
  read_timeout: 10,
  
  # Behavior options
  auto_reconnect: true,
  persistent: true
)
```

### Transport-Specific Options

Each transport may have specific options:

```ruby
# STDOUT specific
SmartMessage::Transport.create(:stdout,
  loopback: true,
  output: "/var/log/messages.log"
)

# Memory specific  
SmartMessage::Transport.create(:memory,
  auto_process: false,
  max_messages: 1000
)

# Redis specific
SmartMessage::Transport.create(:redis,
  url: "redis://localhost:6379",
  db: 1,
  auto_subscribe: true,
  reconnect_attempts: 5,
  reconnect_delay: 2
)
```

## Error Handling

### Transport Errors

Transports should handle their own connection and transmission errors:

```ruby
class RobustTransport < SmartMessage::Transport::Base
  def publish(message_header, message_payload)
    retry_count = 0
    begin
      send_message(message_header, message_payload)
    rescue ConnectionError => e
      retry_count += 1
      if retry_count <= @options[:retry_attempts]
        sleep(@options[:retry_delay])
        retry
      else
        # Log error and potentially fallback
        handle_publish_error(e, message_header, message_payload)
      end
    end
  end
  
  private
  
  def handle_publish_error(error, header, payload)
    # Log the error
    puts "Failed to publish message: #{error.message}"
    
    # Optional: Store for later retry
    store_failed_message(header, payload)
    
    # Optional: Use fallback transport
    fallback_transport&.publish(header, payload)
  end
end
```

### Connection Monitoring

```ruby
class MonitoredTransport < SmartMessage::Transport::Base
  def connected?
    @connection&.ping rescue false
  end
  
  def publish(message_header, message_payload)
    unless connected?
      connect
    end
    
    super
  end
  
  def connect
    @connection = establish_connection(@options)
    puts "Connected to #{@options[:host]}:#{@options[:port]}"
  rescue => e
    puts "Failed to connect: #{e.message}"
    raise
  end
end
```

## Performance Considerations

### Message Batching

For high-throughput scenarios, consider batching:

```ruby
class BatchingTransport < SmartMessage::Transport::Base
  def initialize(options = {})
    super
    @batch = []
    @batch_mutex = Mutex.new
    setup_batch_timer
  end
  
  def publish(message_header, message_payload)
    @batch_mutex.synchronize do
      @batch << [message_header, message_payload]
      
      if @batch.size >= @options[:batch_size]
        flush_batch
      end
    end
  end
  
  private
  
  def flush_batch
    return if @batch.empty?
    
    batch_to_send = @batch.dup
    @batch.clear
    
    send_batch(batch_to_send)
  end
end
```

### Connection Pooling

For database or network transports:

```ruby
class PooledTransport < SmartMessage::Transport::Base
  def initialize(options = {})
    super
    @connection_pool = ConnectionPool.new(
      size: @options[:pool_size] || 5,
      timeout: @options[:pool_timeout] || 5
    ) { create_connection }
  end
  
  def publish(message_header, message_payload)
    @connection_pool.with do |connection|
      connection.send(message_header, message_payload)
    end
  end
end
```

## Testing Transports

### Mock Transport for Testing

```ruby
class MockTransport < SmartMessage::Transport::Base
  attr_reader :published_messages
  
  def initialize(options = {})
    super
    @published_messages = []
  end
  
  def publish(message_header, message_payload)
    @published_messages << {
      header: message_header,
      payload: message_payload,
      published_at: Time.now
    }
    
    # Optionally trigger processing
    receive(message_header, message_payload) if @options[:auto_process]
  end
  
  def clear
    @published_messages.clear
  end
end

# Use in tests
RSpec.describe "Message Publishing" do
  let(:transport) { MockTransport.new(auto_process: true) }
  
  before do
    MyMessage.config do
      transport transport
    end
  end
  
  it "publishes messages" do
    MyMessage.new(data: "test").publish
    
    expect(transport.published_messages).to have(1).message
    expect(transport.published_messages.first[:payload]).to include("test")
  end
end
```

## Next Steps

- [Serializers](serializers.md) - Understanding message serialization
- [Dispatcher](../core-concepts/dispatcher.md) - Message routing and processing
- [Examples](../getting-started/examples.md) - Real-world transport usage patterns