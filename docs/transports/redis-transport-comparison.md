# Transport Comparison

SmartMessage provides multiple transport layers, each designed for different use cases and requirements. This document provides a comprehensive comparison to help you choose the right transport for your application.

## Transport Overview

| Transport | Type | Best For | Key Feature |
|-----------|------|----------|-------------|
| **Memory** | In-Memory Queue | Testing, development | No external dependencies, fast |
| **STDOUT** | Logging/Debug | Development, debugging | Human-readable output |
| **Redis** | Pub/Sub | Production messaging | Distributed, persistent connections |

---

## 🧠 Memory Transport

Perfect for development, testing, and in-memory message queuing.

### Architecture
```
Publisher → Memory Queue → Subscriber
         (thread-safe)   (auto-processing)
```

### Key Characteristics
- **Message Persistence**: In-memory only - lost on restart
- **Pattern Support**: None - direct message class routing
- **Load Balancing**: No - all subscribers receive all messages
- **Threading**: Thread-safe with mutex protection
- **External Dependencies**: None

### Configuration
```ruby
SmartMessage::Transport.create(:memory,
  auto_process: true,     # Automatically route messages to dispatcher
  max_messages: 1000      # Maximum messages to store in memory
)
```

### Use Cases
- **Unit testing** - Predictable, isolated environment
- **Development** - Quick setup without external services
- **In-memory queuing** - Fast processing without persistence
- **Message inspection** - Easy access to all stored messages

### Pros
- ✅ No external dependencies
- ✅ Fastest performance (no serialization)
- ✅ Thread-safe operations
- ✅ Message inspection capabilities
- ✅ Memory overflow protection

### Cons
- ❌ Messages lost on restart
- ❌ Single-process only
- ❌ Memory usage grows with message volume
- ❌ No network distribution

### Example
```ruby
class TestMessage < SmartMessage::Base
  property :data
  
  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
  end
  
  def self.process(decoded_message)
    puts "Processing: #{decoded_message.data}"
  end
end

TestMessage.subscribe
TestMessage.new(data: "Hello World").publish
```

---

## 📄 STDOUT Transport

Ideal for development, debugging, and logging scenarios.

### Architecture
```
Publisher → Console/File Output → Optional Loopback → Subscriber
         (JSON formatting)    (if enabled)      (local processing)
```

### Key Characteristics
- **Message Persistence**: File-based if output specified
- **Pattern Support**: None - logging/debugging focused
- **Load Balancing**: No - single output destination
- **Threading**: Thread-safe file operations
- **External Dependencies**: None

### Configuration
```ruby
SmartMessage::Transport.create(:stdout,
  loopback: true,                    # Process messages locally
  output: "messages.log"             # Output to file instead of console
)
```

### Use Cases
- **Development debugging** - See messages in real-time
- **Application logging** - Structured message logging
- **Message tracing** - Track message flow through system
- **Integration testing** - Verify message content

### Pros
- ✅ Human-readable JSON output
- ✅ File-based persistence option
- ✅ Optional loopback for testing
- ✅ No external dependencies
- ✅ Structured message formatting

### Cons
- ❌ Not suitable for production messaging
- ❌ Single output destination
- ❌ No network distribution
- ❌ Limited throughput for high-volume scenarios

### Example
```ruby
class LogMessage < SmartMessage::Base
  property :level
  property :message
  property :timestamp, default: -> { Time.now.iso8601 }
  
  config do
    transport SmartMessage::Transport.create(:stdout, 
      output: "app.log",
      loopback: false
    )
  end
end

LogMessage.new(level: "INFO", message: "Application started").publish
```

---

## 🔴 Redis Transport

Production-ready Redis pub/sub transport for distributed messaging.

### Architecture
```
Publisher → Redis Channel → Subscriber
         (pub/sub)       (thread-based)
```

### Key Characteristics
- **Message Persistence**: No - fire-and-forget pub/sub
- **Pattern Support**: None - exact channel name matching
- **Load Balancing**: No - all subscribers receive all messages
- **Threading**: Traditional thread-per-subscriber model
- **External Dependencies**: Redis server

### Configuration
```ruby
SmartMessage::Transport.create(:redis,
  url: 'redis://localhost:6379',    # Redis connection URL
  db: 0,                            # Redis database number
  auto_subscribe: true,             # Automatically start subscriber
  reconnect_attempts: 5,            # Connection retry attempts
  reconnect_delay: 1                # Delay between retries (seconds)
)
```

### Use Cases
- **Production messaging** - Reliable distributed messaging
- **Microservices communication** - Service-to-service messaging
- **Real-time applications** - Low-latency message delivery
- **Scalable architectures** - Multiple publishers and subscribers

### Pros
- ✅ Production-ready reliability
- ✅ Distributed messaging support
- ✅ Automatic reconnection handling
- ✅ Low latency (~1ms)
- ✅ High throughput (80K+ messages/second)
- ✅ Automatic serialization (MessagePack/JSON)

### Cons
- ❌ Requires Redis server
- ❌ No message persistence
- ❌ No pattern-based routing
- ❌ No load balancing
- ❌ All subscribers receive all messages

### Example
```ruby
class OrderMessage < SmartMessage::Base
  property :order_id
  property :customer_id
  property :amount
  
  config do
    transport SmartMessage::Transport.create(:redis,
      url: ENV['REDIS_URL'] || 'redis://localhost:6379',
      db: 1
    )
  end
  
  def self.process(decoded_message)
    order = decoded_message
    puts "Processing order #{order.order_id} for $#{order.amount}"
  end
end

OrderMessage.subscribe
OrderMessage.new(
  order_id: "ORD-123",
  customer_id: "CUST-456",
  amount: 99.99
).publish
```

---

## 📊 Feature Comparison Matrix

| Feature | Memory | STDOUT | Redis |
|---------|--------|--------|-------|
| **Message Persistence** | ❌ Memory Only | ✅ File Optional | ❌ No |
| **Network Distribution** | ❌ No | ❌ No | ✅ Yes |
| **External Dependencies** | ❌ None | ❌ None | ✅ Redis |
| **Pattern Matching** | ❌ No | ❌ No | ❌ No |
| **Load Balancing** | ❌ No | ❌ No | ❌ No |
| **Setup Complexity** | Easy | Easy | Medium |
| **Performance (Latency)** | ~0.1ms | ~1ms | ~1ms |
| **Performance (Throughput)** | Highest | Medium | High |
| **Serialization** | None | JSON | MessagePack/JSON |
| **Thread Safety** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Message Inspection** | ✅ Yes | ✅ Yes | ❌ No |
| **Production Ready** | ❌ Testing Only | ❌ Logging Only | ✅ Yes |
| **Horizontal Scaling** | ❌ No | ❌ No | ✅ Yes |

---

## 🎯 Choosing the Right Transport

### Use Memory Transport When:
- ✅ You're writing unit tests
- ✅ You're developing locally
- ✅ You need fast, in-memory message processing
- ✅ You want to inspect messages for testing
- ✅ You don't need persistence or distribution

### Use STDOUT Transport When:
- ✅ You're debugging message flow
- ✅ You need human-readable message logging
- ✅ You're building development tools
- ✅ You want to trace messages in integration tests
- ✅ You need simple file-based message storage

### Use Redis Transport When:
- ✅ You're building production applications
- ✅ You need distributed messaging
- ✅ You have microservices that need to communicate
- ✅ You need reliable, scalable messaging
- ✅ You can manage a Redis server dependency

---

## 🔄 Migration Patterns

### Development → Production
```ruby
# Development (Memory)
class MyMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
  end
end

# Production (Redis)
class MyMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:redis,
      url: ENV['REDIS_URL'] || 'redis://localhost:6379'
    )
  end
end
```

### Environment-Based Configuration
```ruby
class MyMessage < SmartMessage::Base
  config do
    transport case Rails.env
              when 'test'
                SmartMessage::Transport.create(:memory, auto_process: true)
              when 'development'
                SmartMessage::Transport.create(:stdout, loopback: true)
              when 'production'
                SmartMessage::Transport.create(:redis, url: ENV['REDIS_URL'])
              end
  end
end
```

---

## 📈 Performance Characteristics

### Latency Comparison
- **Memory**: ~0.1ms (fastest, no serialization)
- **STDOUT**: ~1ms (JSON formatting overhead)
- **Redis**: ~1ms (network + serialization)

### Throughput Comparison
- **Memory**: Highest (limited by CPU and memory)
- **STDOUT**: Medium (limited by I/O operations)
- **Redis**: High (limited by network and Redis performance)

### Memory Usage
- **Memory**: Grows with message volume (configurable limit)
- **STDOUT**: Minimal (immediate output/write)
- **Redis**: Low (messages not stored locally)

---

## 🛠️ Configuration Examples

### Test Environment
```ruby
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport.create(:memory,
    auto_process: true,
    max_messages: 100
  )
end
```

### Development Environment
```ruby
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport.create(:stdout,
    loopback: true,
    output: "log/messages.log"
  )
end
```

### Production Environment
```ruby
SmartMessage.configure do |config|
  config.default_transport = SmartMessage::Transport.create(:redis,
    url: ENV['REDIS_URL'],
    db: ENV['REDIS_DB']&.to_i || 0,
    reconnect_attempts: 10,
    reconnect_delay: 2
  )
end
```

---

This comparison should help you choose the right transport for your specific use case within the SmartMessage ecosystem. Each transport is optimized for different scenarios and provides the flexibility to grow your application from development to production.