# Redis Transport Examples

This directory contains demonstration programs that use SmartMessage's **Redis Transport** for distributed messaging. These examples show how to build scalable, multi-process applications using Redis pub/sub messaging.

## Transport Overview

The Redis Transport is ideal for:
- **Distributed applications** across multiple processes/servers
- **Real-time messaging** with Redis pub/sub
- **Scalable architectures** with horizontal scaling
- **Cross-service communication** in microservices
- **Event-driven systems** with reliable message delivery

Redis Transport uses Redis's publish/subscribe mechanism, where each message class gets its own Redis channel for efficient routing.

## Prerequisites

Before running these examples:

1. **Install Redis:**
   ```bash
   # macOS
   brew install redis
   
   # Ubuntu/Debian  
   sudo apt install redis-server
   
   # CentOS/RHEL
   sudo yum install redis
   ```

2. **Start Redis server:**
   ```bash
   redis-server
   # Runs on localhost:6379 by default
   ```

3. **Install Redis gem:**
   ```bash
   gem install redis
   ```

## Example Programs

### 🏠 01_smart_home_iot_demo.rb
**Demonstrates:** IoT device communication via Redis pub/sub
**Use Case:** Smart home automation system
**Key Features:**
- **Multiple device types**: Sensors, controllers, and dashboards
- **Real-time data streaming**: Temperature, security, and energy data
- **Automatic fallback**: Uses memory transport if Redis unavailable
- **Channel separation**: Each message type gets dedicated Redis channel
- **Concurrent processing**: Multiple devices publishing simultaneously

**Message Types:**
- `SensorDataMessage` → `SensorDataMessage` channel
- `DeviceCommandMessage` → `DeviceCommandMessage` channel  
- `SecurityAlertMessage` → `SecurityAlertMessage` channel
- `SystemStatusMessage` → `SystemStatusMessage` channel

**Architecture:**
```
┌─────────────┐    Redis Pub/Sub    ┌─────────────┐
│   Sensors   │ ──────────────────► │ Controllers │
│ (Publishers)│                     │(Subscribers)│
└─────────────┘                     └─────────────┘
       │                                   │
       ▼                                   ▼
┌─────────────────────────────────────────────────┐
│              Redis Server                       │
│  Channels: SensorDataMessage,                   │
│           DeviceCommandMessage, etc.            │
└─────────────────────────────────────────────────┘
       ▲                                   ▲
       │                                   │
┌─────────────┐                     ┌─────────────┐
│  Dashboard  │                     │   Alerts    │
│(Subscriber) │                     │(Subscriber) │
└─────────────┘                     └─────────────┘
```

**Running the Demo:**
```bash
cd examples/redis
ruby 01_smart_home_iot_demo.rb
```

**What You'll See:**
1. Device initialization and Redis connection
2. Real-time sensor data publishing
3. Automated device commands and responses
4. Security monitoring and alerts
5. System health reporting

**Redis Commands to Monitor:**
```bash
# Watch active channels
redis-cli PUBSUB CHANNELS

# Monitor all pub/sub activity
redis-cli MONITOR

# Subscribe to specific message type
redis-cli SUBSCRIBE SensorDataMessage
```

## Key Concepts Demonstrated

### 1. **Distributed Messaging**
- Messages published in one process are received by subscribers in other processes
- True distributed communication across multiple Ruby instances

### 2. **Channel-Based Routing** 
- Each SmartMessage class automatically gets its own Redis channel
- Clean separation of message types for efficient filtering

### 3. **Automatic Scaling**
- Multiple subscribers can listen to the same channel
- Publishers and subscribers can be added/removed dynamically

### 4. **Real-Time Communication**
- Near-instantaneous message delivery via Redis pub/sub
- Perfect for time-sensitive applications like IoT monitoring

### 5. **Connection Management**
- Automatic Redis connection handling
- Graceful fallback to memory transport when Redis unavailable

## Redis Transport Configuration

Basic Redis transport setup:
```ruby
SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport.create(:redis,
    url: 'redis://localhost:6379',
    db: 1  # Optional: use specific Redis database
  )
  config.serializer = SmartMessage::Serializer::Json.new
end
```

Per-message class configuration:
```ruby
class MyMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:redis,
      url: 'redis://localhost:6379',
      db: 2
    )
    serializer SmartMessage::Serializer::Json.new
  end
end
```

## Architecture Benefits

### **Scalability**
- Horizontal scaling by adding more publishers/subscribers
- Redis handles connection pooling and load distribution

### **Reliability** 
- Redis provides persistent connections and automatic reconnection
- Message delivery confirmation through Redis pub/sub protocol

### **Performance**
- Redis is optimized for high-throughput messaging
- In-memory storage for minimal latency

### **Flexibility**
- Easy to add new message types (new channels)
- Subscribers can filter by message patterns

## Production Considerations

### **Redis Configuration**
```bash
# Recommended Redis settings for production
maxmemory-policy allkeys-lru
timeout 0
tcp-keepalive 60
maxclients 10000
```

### **Connection Pooling**
```ruby
# Use connection pooling for high-load applications
SmartMessage::Transport.create(:redis,
  url: 'redis://localhost:6379',
  pool: { size: 20, timeout: 5 }
)
```

### **Monitoring and Debugging**
```bash
# Monitor Redis performance
redis-cli INFO stats
redis-cli MONITOR | grep PUBLISH
redis-cli CLIENT LIST
```

## Testing Distributed Scenarios

Run multiple terminal sessions to test distributed messaging:

**Terminal 1 (Publisher):**
```ruby
# Create a publisher-only script
sensor = SmartHomeSensor.new('living-room')
loop do
  sensor.publish_temperature_reading
  sleep(2)
end
```

**Terminal 2 (Subscriber):**
```ruby
# Create a subscriber-only script
SensorDataMessage.subscribe
# Keep process alive to receive messages
sleep
```

## Next Steps

After mastering Redis Transport:
- **[Redis Queue Examples](../redis_queue/)** - For guaranteed message delivery
- **[Redis Enhanced Examples](../redis_enhanced/)** - For advanced Redis patterns
- **[Memory Examples](../memory/)** - For development and testing

The Redis transport provides the foundation for building production-ready, distributed SmartMessage applications.