# Redis Queue Transport Examples

This directory contains comprehensive examples demonstrating all capabilities of the Redis Queue Transport for SmartMessage. Each example builds upon the previous ones, showcasing different aspects of the transport's functionality.

## 🚀 Quick Start

Before running the examples, ensure you have:

1. **Redis server running** on localhost:6379
2. **SmartMessage gem** installed with Redis Queue Transport
3. **Ruby 2.7+** installed

```bash
# Start Redis (if not already running)
redis-server

# Run any example
ruby 01_basic_messaging.rb
```

## 📚 Examples Overview

### 1. Basic Messaging (`01_basic_messaging.rb`)
**Duration: ~30 seconds**

Demonstrates fundamental Redis Queue Transport operations:
- Simple message publishing and subscription
- Multiple message types (Welcome, Order, Alert)
- Basic queue-based reliable delivery
- Performance testing with rapid message publishing
- Message processing with timestamps

**Key Concepts:**
- Queue-based messaging vs traditional pub/sub
- Automatic message serialization
- Reliable message delivery
- High-throughput publishing

### 2. Pattern Routing (`02_pattern_routing.rb`)
**Duration: ~45 seconds**

Advanced pattern-based message routing capabilities:
- RabbitMQ-style wildcard patterns (`#`, `*`)
- FROM/TO-based message routing
- Message type filtering
- Broadcast and targeted messaging
- Complex multi-pattern subscriptions

**Key Concepts:**
- Enhanced routing keys: `namespace.message_type.from_uuid.to_uuid`
- Pattern matching with `#.*.service_name`
- Multi-service message coordination
- Surgical message precision

### 3. Fluent API (`03_fluent_api.rb`)
**Duration: ~40 seconds**

Fluent interface for building complex subscriptions:
- Chainable subscription builders
- Dynamic pattern construction
- Runtime subscription modification
- Complex criteria combinations
- Pattern inspection and debugging

**Key Concepts:**
- Fluent API: `transport.where.from().to().subscribe`
- Dynamic subscription building
- Type-safe subscription construction
- Pattern generation and analysis

### 4. Load Balancing (`04_load_balancing.rb`)
**Duration: ~60 seconds**

Consumer groups and load distribution:
- Multiple workers sharing queues
- Consumer group management
- High-volume load testing
- Priority-based routing
- Mixed-performance worker handling

**Key Concepts:**
- Consumer groups for work distribution
- Redis BRPOP for automatic load balancing
- Round-robin task distribution
- Fault-tolerant worker coordination

### 5. Microservices Architecture (`05_microservices.rb`)
**Duration: ~75 seconds**

Complete microservices communication patterns:
- Service-to-service messaging
- Request/response patterns
- Event-driven architecture
- API Gateway coordination
- Multi-service workflows

**Key Concepts:**
- Microservice message patterns
- Asynchronous service communication
- Event bus implementation
- Service isolation and independence
- End-to-end workflow orchestration

### 6. Emergency Alert System (`06_emergency_alerts.rb`)
**Duration: ~90 seconds**

Real-world emergency response coordination:
- Multi-agency alert distribution
- Severity-based routing
- Citizen reporting integration
- Real-time response tracking
- Mass casualty incident handling

**Key Concepts:**
- Critical system reliability
- Multi-stakeholder coordination
- Geographic-based routing
- Priority escalation systems
- Real-time status tracking

### 7. Queue Management (`07_queue_management.rb`)
**Duration: ~60 seconds**

Administrative and monitoring capabilities:
- Real-time queue statistics
- Health monitoring and alerting
- Performance metrics analysis
- Administrative operations
- System optimization recommendations

**Key Concepts:**
- Queue monitoring and administration
- Performance optimization
- System health analysis
- Resource utilization tracking
- Automated recommendations

## 🎯 Running Examples

### Run Individual Examples
```bash
# Basic functionality
ruby 01_basic_messaging.rb

# Advanced routing
ruby 02_pattern_routing.rb

# Fluent API usage
ruby 03_fluent_api.rb

# Load balancing demo
ruby 04_load_balancing.rb

# Microservices architecture
ruby 05_microservices.rb

# Emergency alert system
ruby 06_emergency_alerts.rb

# Queue management
ruby 07_queue_management.rb
```

### Run All Examples Sequentially
```bash
# Run all examples with delays
for file in 0{1..7}_*.rb; do
  echo "Running $file..."
  ruby "$file"
  echo "Completed $file. Press Enter to continue..."
  read
done
```

### Clean Redis Between Examples
Each example uses a different Redis database (1-7) to avoid conflicts, but you can clean up:

```bash
# Clean all example databases
redis-cli FLUSHALL

# Or clean specific database
redis-cli -n 1 FLUSHDB  # Clean database 1
```

## 📊 Example Comparison Matrix

| Feature | Example | Database | Duration | Complexity | Prerequisites |
|---------|---------|----------|----------|------------|---------------|
| **Basic Messaging** | 01 | 1 | 30s | Beginner | None |
| **Pattern Routing** | 02 | 2 | 45s | Intermediate | Understand basic messaging |
| **Fluent API** | 03 | 3 | 40s | Intermediate | Pattern routing knowledge |
| **Load Balancing** | 04 | 4 | 60s | Advanced | Multi-threading concepts |
| **Microservices** | 05 | 5 | 75s | Advanced | Service architecture |
| **Emergency Alerts** | 06 | 6 | 90s | Expert | Complex systems |
| **Queue Management** | 07 | 7 | 60s | Expert | All previous examples |

## 🔧 Configuration Examples

### Transport Configuration Patterns

```ruby
# Basic configuration
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: 'redis://localhost:6379',
    db: 1,
    queue_prefix: 'my_app',
    consumer_group: 'workers'
  }
end

# High-performance configuration
transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 0,
  queue_prefix: 'high_perf',
  consumer_group: 'fast_workers',
  block_time: 100,        # Fast polling
  max_queue_length: 50000 # Large queues
)

# Development configuration
transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 15,                 # Test database
  queue_prefix: 'dev',
  consumer_group: 'dev_workers',
  block_time: 1000,       # Slower polling for debugging
  max_retries: 1          # Quick failure for development
)
```

### Message Class Patterns

```ruby
# Basic message
class SimpleMessage < SmartMessage::Base
  transport :redis_queue
  property :content, required: true
end

# Enhanced message with routing
class RoutedMessage < SmartMessage::Base
  transport :redis_queue, {
    queue_prefix: 'routed_msgs',
    consumer_group: 'routed_workers'
  }
  
  property :data, required: true
  property :priority, default: 'normal'
  
  def process
    puts "Processing: #{data} [#{priority}]"
  end
end

# Service message with validation
class ServiceMessage < SmartMessage::Base
  transport :redis_queue
  
  property :service_name, required: true
  property :operation, required: true
  property :payload, default: {}
  
  validate :service_name, inclusion: ['user_service', 'order_service']
  validate :operation, format: /\A[a-z_]+\z/
  
  def process
    # Service-specific processing
    send("handle_#{operation}")
  end
end
```

## 🚨 Troubleshooting

### Common Issues

1. **Redis Connection Failed**
   ```
   Error: Redis::CannotConnectError
   Solution: Ensure Redis is running on localhost:6379
   ```

2. **Queue Not Processing Messages**
   ```
   Problem: Messages published but not processed
   Solution: Check that subscribers are properly set up with matching patterns
   ```

3. **Pattern Not Matching**
   ```
   Problem: Subscription pattern doesn't match published messages
   Solution: Verify routing key format and wildcard usage
   ```

### Debugging Tips

```ruby
# Enable debug logging
transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  debug: true  # Enable debug output
)

# Check queue statistics
stats = transport.queue_stats
puts "Queue stats: #{stats}"

# Inspect routing table
routing_table = transport.routing_table
puts "Routing: #{routing_table}"

# Monitor Redis directly
# redis-cli MONITOR  # Shows all Redis commands
```

## 📈 Performance Guidelines

### Message Publishing
- **High throughput**: Batch publish multiple messages
- **Low latency**: Use smaller queue prefixes
- **Reliability**: Enable persistence in Redis configuration

### Consumer Configuration
- **CPU intensive**: Fewer consumers per core
- **I/O intensive**: More consumers per core
- **Memory intensive**: Monitor queue lengths

### Queue Management
- **Monitor queue lengths**: Set up alerts for queue buildup
- **Consumer scaling**: Add/remove consumers based on load
- **Pattern optimization**: Use specific patterns when possible

## 🔗 Related Documentation

- [Redis Queue Transport API Documentation](../REDIS_QUEUE_TRANSPORT.md)
- [Redis Queue Architecture](../REDIS_QUEUE_ARCHITECTURE.md)
- [SmartMessage Core Documentation](../README.md)
- [Transport Comparison Guide](../REDIS_VS_RABBITMQ_COMPARISON.md)

## 💡 Best Practices

1. **Start with basic examples** and progress to advanced ones
2. **Use different Redis databases** for different environments
3. **Monitor queue health** regularly in production
4. **Test failure scenarios** with your message handlers
5. **Implement proper error handling** in message processors
6. **Use meaningful queue prefixes** for organization
7. **Document your routing patterns** for team members

## 🎓 Learning Path

For best understanding, run examples in this order:

1. **Foundations**: 01_basic_messaging.rb
2. **Routing**: 02_pattern_routing.rb  
3. **API Design**: 03_fluent_api.rb
4. **Scalability**: 04_load_balancing.rb
5. **Architecture**: 05_microservices.rb
6. **Real-world Application**: 06_emergency_alerts.rb
7. **Operations**: 07_queue_management.rb

Each example builds upon concepts from previous ones, providing a comprehensive learning experience for Redis Queue Transport mastery.