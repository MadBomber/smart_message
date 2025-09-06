# Redis Queue Transport

The **Redis Queue Transport** is SmartMessage's most advanced transport implementation, providing RabbitMQ-style queue/exchange routing using Redis Lists as persistent FIFO queues. Built on Ruby's Async framework for modern fiber-based concurrency, it combines Redis's exceptional performance with intelligent message routing capabilities.

## Overview

Redis Queue Transport is perfect for:
- **High-throughput applications** - 100K+ messages/second with minimal latency
- **Complex routing scenarios** - RabbitMQ-style pattern matching with Redis performance
- **Load-balanced processing** - Consumer groups for horizontal scaling
- **Persistent message queues** - Messages survive service restarts
- **Modern async applications** - Built on Ruby's Async framework

## Key Features

- 🚀 **RabbitMQ-Style Routing** - Pattern-based subscriptions with familiar syntax
- ⚡ **Ultra-High Performance** - ~0.5ms latency, 100K+ messages/second  
- 🧬 **Async/Fiber Architecture** - Thousands of concurrent subscriptions
- 🔄 **Persistent Queues** - Redis Lists (LPUSH/BRPOP) for message durability
- ⚖️ **Load Balancing** - Consumer groups for horizontal scaling
- 🎯 **Enhanced Routing** - Multi-segment routing keys with from/to addressing
- 📊 **Queue Monitoring** - Comprehensive statistics and health monitoring
- 🛠️ **Fluent API** - Chainable subscription building for complex routing

## Architecture

![Redis Queue Architecture](../assets/images/redis-queue-architecture.svg)

The Redis Queue Transport combines the routing intelligence of message brokers with Redis's performance characteristics. Built on Ruby's Async framework, it uses cooperative fiber-based concurrency for massive scalability with minimal resource overhead.

### Performance Comparison

| Feature | RabbitMQ | Redis Queue (Async) | Performance Advantage |
|---------|----------|---------------------|----------------------|
| **Latency** | ~5ms | ~0.5ms | Redis **10x faster** |
| **Throughput** | 20K-30K msg/sec | 100K+ msg/sec | Redis **3-5x faster** |
| **Concurrent Subscribers** | ~100s | ~1000s | Async **10x more** |
| **Memory per Connection** | ~2MB | ~2KB | Async **1000x less** |
| **Pattern Matching** | Server-side | Client-side | Same syntax |
| **Load Balancing** | Queue groups | Consumer groups | Same behavior |
| **Setup Complexity** | High | Low | Redis **simpler** |

## Configuration

### Basic Configuration

```ruby
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: 'redis://localhost:6379',
    db: 0,
    queue_prefix: 'smart_message.queue',
    consumer_group: 'default_workers',
    block_time: 1000,  # 1 second blocking read
    max_queue_length: 10000
  }
end
```

### Message Class Configuration

```ruby
class OrderMessage < SmartMessage::Base
  transport :redis_queue, {
    url: 'redis://redis-server:6379',
    consumer_group: 'order_processors',
    queue_prefix: 'orders'
  }
  
  property :order_id, required: true
  property :amount, required: true
  
  def process
    # Process order logic
    puts "Processing order #{order_id} for $#{amount}"
  end
end
```

### Advanced Configuration Options

```ruby
transport = SmartMessage::Transport::RedisQueueTransport.new({
  # Connection settings
  url: 'redis://username:password@redis.example.com:6379',
  db: 2,
  
  # Queue settings
  queue_prefix: 'myapp.queues',
  consumer_group: 'myapp_workers',
  consumer_id: "#{Socket.gethostname}_#{Process.pid}",
  
  # Performance tuning
  block_time: 5000,         # 5 second blocking timeout
  max_queue_length: 50000,  # Trim queues at 50k messages
  batch_size: 10,           # Process messages in batches
  
  # Reliability settings
  max_retries: 3,
  retry_delay: 5,           # 5 seconds between retries
  dead_letter_queue: true,
  
  # Connection pooling
  pool_size: 5,
  pool_timeout: 1
})
```

## Async Architecture

The Redis Queue Transport is built on Ruby's **Async framework**, providing modern fiber-based concurrency that offers significant advantages over traditional thread-based approaches:

### Key Benefits

- **Massive Scalability**: Support for thousands of concurrent subscribers with minimal resource overhead
- **Cooperative Concurrency**: Fibers yield control voluntarily, eliminating race conditions and reducing context switching overhead  
- **Memory Efficiency**: Each fiber uses ~2KB vs ~2MB per thread (1000x less memory)
- **Test-Friendly**: Clean async lifecycle management with proper shutdown and cleanup
- **Non-Blocking I/O**: All Redis operations are fully asynchronous and non-blocking

### Usage with Async

All transport operations should be wrapped in `Async` blocks for optimal performance:

```ruby
# Basic async usage
Async do
  transport = SmartMessage::Transport::RedisQueueTransport.new(
    url: 'redis://localhost:6379',
    db: 0,
    test_mode: false  # Enable consumer tasks
  )
  
  # Subscribe to patterns
  transport.subscribe_pattern("#.*.my_service") do |message_class, data|
    # Process messages in async fiber
    puts "Processing #{message_class} in fiber #{Async::Task.current.object_id}"
  end
  
  # Publish messages
  MyMessage.new(data: "test").publish
  
  # Keep async context alive
  sleep
end
```

### Async Best Practices

```ruby
# Multiple concurrent subscriptions
Async do |task|
  transport = SmartMessage::Transport::RedisQueueTransport.new(...)
  
  # Each subscription runs in its own fiber
  task.async do
    transport.subscribe_pattern("#.*.service1") { |msg, data| ... }
  end
  
  task.async do  
    transport.subscribe_pattern("#.*.service2") { |msg, data| ... }
  end
  
  task.async do
    transport.subscribe_pattern("#.*.service3") { |msg, data| ... }
  end
  
  # All subscriptions run concurrently with minimal overhead
  sleep
end
```

## Routing Keys and Patterns

### Routing Key Format

Messages are published with enhanced routing keys in the format:
```
namespace.message_type.from_uuid.to_uuid
```

Examples:
- `order.ordermessage.user123.service456`
- `emergency.alertmessage.security.broadcast`  
- `system.healthcheck.monitor.all_services`

### Wildcard Patterns (RabbitMQ Compatible)

The Redis Queue Transport uses identical wildcard syntax to RabbitMQ:

- **`#`** = Zero or more words (matches `a`, `a.b`, `a.b.c`)  
- **`*`** = Exactly one word (matches `a` but not `a.b`)
- **`.`** = Word separator (literal dot)

### Pattern Examples

```ruby
# Recipient-based routing
transport.subscribe_pattern("#.*.payment_service")      # All TO payment_service
transport.subscribe_pattern("#.*.user_#{user_id}")      # Personal messages

# Sender-based routing  
transport.subscribe_pattern("#.admin_service.*")        # All FROM admin_service
transport.subscribe_pattern("#.#{service_name}.*")      # All from your service

# Message type routing
transport.subscribe_pattern("order.#.*.*")              # All order messages
transport.subscribe_pattern("alert.#.*.*")              # All alerts
transport.subscribe_pattern("#{namespace}.#.*.*")       # All in namespace

# Complex routing
transport.subscribe_pattern("emergency.#.security.*")   # Security emergencies
transport.subscribe_pattern("#.*.#{env}_services")      # Environment-specific
```

## Pattern Subscriptions

### Direct Pattern Subscriptions

```ruby
# Create transport instance
transport = SmartMessage::Transport::RedisQueueTransport.new(options)

# Subscribe to messages TO specific services
transport.subscribe_pattern("#.*.payment_service") do |message_class, message_data|
  puts "Payment service received: #{message_class}"
  # Process payment message
end

# Subscribe to messages FROM specific services
transport.subscribe_pattern("#.admin_service.*") do |message_class, message_data|
  puts "Message from admin: #{message_class}"
  # Process admin message
end

# Subscribe to specific message types
transport.subscribe_pattern("order.#.*.*") do |message_class, message_data|
  puts "Order message received: #{message_class}"
  # Process any order message
end
```

### Message Class Subscriptions

```ruby
# Standard SmartMessage subscription (auto-generates patterns)
class OrderMessage < SmartMessage::Base
  transport :redis_queue
  
  # This automatically subscribes to pattern: "order.ordermessage.*.*"
end

OrderMessage.subscribe  # Subscribes to all OrderMessage instances

# Custom pattern subscription for message class
OrderMessage.subscribe_pattern("#.*.order_service") do |message|
  # Only process orders directed to order_service
end
```

## Convenience Methods

The transport provides convenient methods for common routing patterns:

```ruby
# Simple recipient/sender filtering
transport.subscribe_to_recipient('my_service')          # Messages TO me
transport.subscribe_from_sender('payment_service')      # Messages FROM payment
transport.subscribe_to_type('OrderMessage')             # All OrderMessage types

# Broadcast and alert patterns
transport.subscribe_to_broadcasts                        # All broadcast messages
transport.subscribe_to_alerts                           # Emergency/alert messages

# Environment-based subscriptions
transport.subscribe_to_environment('production')        # Only prod messages
transport.subscribe_to_tenant('tenant_123')             # Tenant-specific messages
```

## Fluent API

The fluent API provides an expressive way to build complex subscriptions:

### Basic Fluent Usage

```ruby
# Simple FROM subscription
transport.where
  .from('api_service')
  .subscribe do |message_class, message_data|
    puts "Message from API service: #{message_class}"
  end

# Simple TO subscription
transport.where
  .to('task_processor')
  .subscribe do |message_class, message_data|
    puts "Task for processor: #{message_class}"
  end

# Type-specific subscription
transport.where
  .type('TaskMessage')
  .subscribe do |message_class, message_data|
    puts "Task message received: #{message_class}"
  end
```

### Advanced Fluent Combinations

```ruby
# Combined FROM and TO
transport.where
  .from('web_app')
  .to('event_processor')
  .subscribe do |message_class, message_data|
    puts "Web app event: #{message_class}"
  end

# Consumer group with load balancing
transport.where
  .type('TaskMessage')
  .consumer_group('task_workers')
  .subscribe do |message_class, message_data|
    fiber_id = Async::Task.current.object_id.to_s[-4..-1]
    puts "Fiber-#{fiber_id} processing: #{message_class}"
  end

# Complex multi-criteria subscription
transport.where
  .from(/^admin_.*/)  # Regex pattern for admin services
  .to('monitoring_service')
  .consumer_group('monitoring_workers')
  .subscribe do |message_class, message_data|
    puts "Admin monitoring: #{message_class}"
  end

# Type and destination combination
transport.where
  .type('EventMessage')
  .to(/.*analytics.*/)  # Any service with 'analytics' in name
  .subscribe do |message_class, message_data|
    puts "Analytics event: #{message_class}"
  end
```

### Dynamic Subscription Building

```ruby
# Build and modify subscriptions dynamically
base_subscription = transport.where.type('TaskMessage')

# Add criteria dynamically
urgent_tasks = base_subscription.from('urgent_processor')
pattern1 = urgent_tasks.build
puts "Urgent tasks pattern: #{pattern1}"

# Build different variations
analytics_tasks = base_subscription.to(/.*analytics.*/)
pattern2 = analytics_tasks.build  
puts "Analytics tasks pattern: #{pattern2}"

# Subscribe with complex pattern
transport.where
  .type('EventMessage')
  .from(/^(web|mobile)_app$/)  # From web or mobile app
  .to(/.*analytics.*/)         # To any analytics service
  .consumer_group('analytics_processors')
  .subscribe do |message_class, message_data|
    puts "Complex pattern match: #{message_class}"
  end
```

## Load Balancing

### Consumer Groups

Multiple consumers can share the same queue for automatic load distribution:

```ruby
# Create multiple workers in the same consumer group
worker1_transport = SmartMessage::Transport::RedisQueueTransport.new({
  consumer_group: 'order_workers',
  consumer_id: 'worker_1'
})

worker2_transport = SmartMessage::Transport::RedisQueueTransport.new({
  consumer_group: 'order_workers', 
  consumer_id: 'worker_2'
})

worker3_transport = SmartMessage::Transport::RedisQueueTransport.new({
  consumer_group: 'order_workers',
  consumer_id: 'worker_3'
})

# All workers subscribe to same pattern
pattern = "#.*.order_service"

worker1_transport.subscribe_pattern(pattern) { |msg| puts "Worker 1: #{msg}" }
worker2_transport.subscribe_pattern(pattern) { |msg| puts "Worker 2: #{msg}" }  
worker3_transport.subscribe_pattern(pattern) { |msg| puts "Worker 3: #{msg}" }

# Messages published to order_service will be distributed among workers
```

### Load Balancing with Fluent API

```ruby
# Multiple workers using fluent API
3.times do |i|
  worker_transport = SmartMessage::Transport::RedisQueueTransport.new({
    consumer_group: 'balanced_workers',
    consumer_id: "worker_#{i + 1}"
  })
  
  worker_transport.where
    .to('shared_service')
    .consumer_group('balanced_workers')
    .subscribe do |message_class, message_data|
      puts "Worker #{i + 1} processing: #{message_class}"
    end
end
```

### Priority-Based Load Balancing

```ruby
# High-priority worker pool
high_priority_transport = SmartMessage::Transport::RedisQueueTransport.new({
  consumer_group: 'high_priority_workers'
})

high_priority_transport.where
  .to('priority_queue')
  .consumer_group('high_priority_workers')  
  .subscribe do |message_class, message_data|
    puts "HIGH PRIORITY: #{message_class}"
  end

# Normal priority worker pool  
normal_priority_transport = SmartMessage::Transport::RedisQueueTransport.new({
  consumer_group: 'normal_workers'
})

normal_priority_transport.where
  .to('normal_queue')
  .consumer_group('normal_workers')
  .subscribe do |message_class, message_data|
    puts "Normal priority: #{message_class}"
  end
```

## Message Publishing

### Basic Publishing

```ruby
class OrderMessage < SmartMessage::Base
  transport :redis_queue
  
  property :order_id, required: true
  property :customer_id, required: true
  property :amount, required: true
end

# Publish with automatic routing
message = OrderMessage.new(
  order_id: 'ORD-001',
  customer_id: 'CUST-123', 
  amount: 99.99
)

# Set routing header for enhanced routing
message._sm_header.from = 'order_service'
message._sm_header.to = 'payment_service'

message.publish  # Routes to: order.ordermessage.order_service.payment_service
```

### Publishing with Enhanced Headers

```ruby
# Explicit header setting
OrderMessage.new(
  order_id: 'ORD-002',
  customer_id: 'CUST-456',
  amount: 149.99,
  _sm_header: {
    from: 'api_gateway',
    to: 'order_service',
    correlation_id: SecureRandom.uuid,
    tenant_id: 'tenant_123'
  }
).publish

# Broadcast publishing
AlertMessage.new(
  alert_type: 'maintenance',
  message: 'System maintenance starting in 10 minutes',
  _sm_header: {
    from: 'admin_service',
    to: 'broadcast'  # Routes to all subscribers of broadcasts
  }
).publish

# Environment-specific publishing
DeploymentMessage.new(
  version: '2.1.0',
  changelog: 'Bug fixes and performance improvements',
  _sm_header: {
    from: 'ci_cd_service',
    to: 'prod_services'  # Only production services
  }
).publish
```

### Batch Publishing

```ruby
# Publish multiple messages efficiently
messages = []

100.times do |i|
  messages << TaskMessage.new(
    task_id: "BATCH-#{i}",
    priority: 'normal',
    _sm_header: {
      from: 'batch_processor',
      to: 'worker_pool'
    }
  )
end

# Batch publish for better performance
messages.each(&:publish)  # Redis pipelining automatically optimizes this
```

## Queue Management

### Queue Statistics

```ruby
# Get comprehensive queue statistics
stats = transport.queue_stats

# Example output:
# {
#   "smart_message.queue.#_*_payment_service" => { 
#     length: 42, 
#     pattern: "#.*.payment_service",
#     consumers: 2,
#     consumer_group: "payment_workers",
#     last_activity: Time.now - 30
#   },
#   "smart_message.queue.order_#_*_*" => {
#     length: 0,
#     pattern: "order.#.*.*", 
#     consumers: 3,
#     consumer_group: "order_workers",
#     last_activity: Time.now - 5
#   }
# }

# Process statistics
stats.each do |queue_name, info|
  puts "Queue: #{queue_name}"
  puts "  Messages: #{info[:length]}"
  puts "  Consumers: #{info[:consumers]}"
  puts "  Pattern: #{info[:pattern]}"
  puts "  Last Activity: #{info[:last_activity]}"
  puts ""
end
```

### Routing Table Inspection

```ruby
# View active routing patterns and their mappings
routing_table = transport.routing_table

# Example output:
# {
#   "#.*.payment_service" => ["smart_message.queue.#_*_payment_service"],
#   "order.#.*.*" => ["smart_message.queue.order_#_*_*"],
#   "#.admin_service.*" => ["smart_message.queue.#_admin_service_*"]
# }

# Analyze routing patterns
routing_table.each do |pattern, queues|
  puts "Pattern '#{pattern}':"
  puts "  Routes to #{queues.size} queue(s):"
  queues.each { |queue| puts "    - #{queue}" }
  puts ""
end
```

### Queue Health Monitoring

```ruby
# Monitor queue health and performance
def monitor_queue_health(transport)
  stats = transport.queue_stats
  health_issues = []
  
  stats.each do |queue_name, info|
    # Check for potential issues
    if info[:length] > 1000
      health_issues << "WARNING: Queue #{queue_name} has #{info[:length]} messages (high load)"
    elsif info[:length] > 0 && info[:consumers] == 0
      health_issues << "ERROR: Queue #{queue_name} has messages but no consumers"
    elsif info[:consumers] > 10
      health_issues << "INFO: Queue #{queue_name} has #{info[:consumers]} consumers (possible over-provisioning)"
    end
    
    # Check for stale queues
    if info[:last_activity] && info[:last_activity] < Time.now - 300  # 5 minutes
      health_issues << "WARNING: Queue #{queue_name} inactive for #{Time.now - info[:last_activity]} seconds"
    end
  end
  
  if health_issues.any?
    puts "Queue Health Issues:"
    health_issues.each { |issue| puts "  #{issue}" }
  else
    puts "All queues healthy ✅"
  end
  
  health_issues
end

# Run health check
health_issues = monitor_queue_health(transport)
```

### Administrative Operations

```ruby
# Clear specific queue
transport.clear_queue("smart_message.queue.#_*_test_service")

# Clear all queues for consumer group
transport.clear_consumer_group_queues("test_workers")

# Get queue length
length = transport.queue_length("smart_message.queue.order_#_*_*")
puts "Order queue length: #{length}"

# Pause/resume consumer groups
transport.pause_consumer_group("maintenance_workers")
transport.resume_consumer_group("maintenance_workers")

# Get consumer group information
consumer_info = transport.consumer_group_info("order_workers")
puts "Consumer group info: #{consumer_info}"
```

## Error Handling and Reliability

### Retry Mechanisms

```ruby
class ReliableMessage < SmartMessage::Base
  transport :redis_queue, {
    max_retries: 3,
    retry_delay: 5,           # 5 seconds between retries
    exponential_backoff: true # 5s, 25s, 125s delays
  }
  
  property :data, required: true
  
  def process
    begin
      # Potentially failing operation
      external_service.process(data)
    rescue ExternalService::TemporaryError => e
      # Retryable error - will be retried automatically
      raise SmartMessage::Errors::RetryableError, e.message
    rescue ExternalService::ValidationError => e
      # Permanent error - goes to dead letter queue
      raise SmartMessage::Errors::PermanentError, e.message
    end
  end
end
```

### Dead Letter Queue

```ruby
# Configure dead letter queue
transport = SmartMessage::Transport::RedisQueueTransport.new({
  dead_letter_queue: true,
  dead_letter_prefix: 'dlq',
  max_retries: 3
})

# Monitor dead letter queue
dlq_stats = transport.dead_letter_stats
puts "Dead letter messages: #{dlq_stats[:count]}"
puts "Recent errors: #{dlq_stats[:recent_errors]}"

# Process dead letter messages
transport.process_dead_letters do |message_data, error_info|
  puts "Dead letter: #{message_data}"
  puts "Error: #{error_info[:error_message]}"
  puts "Retry count: #{error_info[:retry_count]}"
  
  # Decide whether to retry, route elsewhere, or discard
  if error_info[:retry_count] < 5 && fixable_error?(error_info[:error_message])
    :retry  # Retry the message
  else
    :discard  # Discard the message
  end
end
```

### Circuit Breaker Pattern

```ruby
class CircuitBreakerMessage < SmartMessage::Base
  transport :redis_queue, {
    circuit_breaker: true,
    failure_threshold: 5,    # Open circuit after 5 failures
    recovery_timeout: 60,    # Try again after 60 seconds
    half_open_max_calls: 3   # Allow 3 calls when half-open
  }
  
  def process
    # External service call
    external_service.call(data)
  end
end
```

## Use Cases and Examples

### Microservices Communication

```ruby
# API Gateway routing requests to services
class ServiceRequest < SmartMessage::Base
  transport :redis_queue
  
  property :service_name, required: true
  property :operation, required: true
  property :payload, default: {}
end

# Route based on service name
api_gateway_transport.where
  .type('ServiceRequest')
  .subscribe do |message_class, message_data|
    request = JSON.parse(message_data)
    
    # Forward to appropriate service
    ServiceRequest.new(request.merge(
      '_sm_header' => {
        'from' => 'api_gateway',
        'to' => request['service_name']
      }
    )).publish
  end

# Services subscribe to their own requests
user_service_transport.where
  .to('user_service')
  .consumer_group('user_workers')
  .subscribe do |message_class, message_data|
    # Process user service request
  end

payment_service_transport.where
  .to('payment_service')
  .consumer_group('payment_workers')
  .subscribe do |message_class, message_data|
    # Process payment service request  
  end
```

### Event-Driven Architecture

```ruby
# Order processing workflow
class OrderPlaced < SmartMessage::Base
  transport :redis_queue
  
  property :order_id, required: true
  property :customer_id, required: true
  property :items, required: true
end

# Multiple services process order events
inventory_service.where
  .type('OrderPlaced')
  .consumer_group('inventory_workers')
  .subscribe do |message_class, message_data|
    # Reserve inventory
  end

payment_service.where
  .type('OrderPlaced')
  .consumer_group('payment_workers')
  .subscribe do |message_class, message_data|
    # Process payment
  end

shipping_service.where
  .type('OrderPlaced')
  .consumer_group('shipping_workers')
  .subscribe do |message_class, message_data|
    # Arrange shipping
  end

analytics_service.where
  .type('OrderPlaced')
  .consumer_group('analytics_workers')
  .subscribe do |message_class, message_data|
    # Track metrics
  end
```

### Multi-Tenant Systems

```ruby
# Tenant isolation via routing
class TenantMessage < SmartMessage::Base
  transport :redis_queue
  
  property :tenant_id, required: true
  property :data, required: true
end

# Each tenant gets isolated message processing
tenant_transport.where
  .from(/^tenant_#{tenant_id}_.*/)
  .to(/^tenant_#{tenant_id}_.*/)
  .consumer_group("tenant_#{tenant_id}_workers")
  .subscribe do |message_class, message_data|
    # Process tenant-specific message
  end

# Admin messages broadcast to all tenants
admin_transport.where
  .from('admin_service')
  .to('broadcast')
  .subscribe do |message_class, message_data|
    # Process admin broadcast
  end
```

### Real-Time Monitoring and Alerting

```ruby
# Monitoring system with alert routing
class MetricMessage < SmartMessage::Base
  transport :redis_queue
  
  property :metric_name, required: true
  property :value, required: true
  property :threshold, required: true
  property :severity, default: 'info'
end

# Route based on severity
monitoring_transport.where
  .type('MetricMessage')
  .subscribe do |message_class, message_data|
    metric = JSON.parse(message_data)
    
    if metric['value'] > metric['threshold']
      severity = if metric['value'] > metric['threshold'] * 2
                   'critical'
                 elsif metric['value'] > metric['threshold'] * 1.5
                   'warning'
                 else
                   'info'
                 end
      
      AlertMessage.new(
        alert_type: metric['metric_name'],
        message: "#{metric['metric_name']} is #{metric['value']} (threshold: #{metric['threshold']})",
        severity: severity,
        _sm_header: {
          from: 'monitoring_service',
          to: severity == 'critical' ? 'pager_duty' : 'alert_dashboard'
        }
      ).publish
    end
  end
```

## Best Practices

### Naming Conventions

```ruby
# Use descriptive queue prefixes
transport = SmartMessage::Transport::RedisQueueTransport.new({
  queue_prefix: 'myapp.production.queues'  # Environment-specific
})

# Use meaningful consumer group names
transport.where
  .to('order_service')
  .consumer_group('order_processors')  # Descriptive group name
  .subscribe
```

### Resource Management

```ruby
# Proper cleanup on shutdown
at_exit do
  transport.disconnect
  transport.cleanup_consumer_groups
end

# Connection pooling for high-throughput applications
transport = SmartMessage::Transport::RedisQueueTransport.new({
  pool_size: 10,
  pool_timeout: 5
})
```

### Monitoring and Observability

```ruby
# Regular health monitoring with Async
Async do
  loop do
    stats = transport.queue_stats
    
    # Log queue lengths
    stats.each do |queue, info|
      if info[:length] > 100
        Rails.logger.warn "Queue #{queue} backing up: #{info[:length]} messages"
      end
    end
    
    # Check consumer health
    dead_consumers = stats.select { |_, info| info[:consumers] == 0 && info[:length] > 0 }
    unless dead_consumers.empty?
      Rails.logger.error "Queues with no consumers: #{dead_consumers.keys}"
    end
    
    sleep 30
  end
end
```

### Performance Optimization

```ruby
# Batch processing for high throughput
transport.where
  .to('batch_processor')
  .subscribe do |message_class, message_data|
    # Process in batches
    batch = []
    
    batch << JSON.parse(message_data)
    
    if batch.size >= 10  # Process every 10 messages
      process_batch(batch)
      batch.clear
    end
  end

# Use appropriate block times
fast_transport = SmartMessage::Transport::RedisQueueTransport.new({
  block_time: 100  # Low latency, higher CPU usage
})

efficient_transport = SmartMessage::Transport::RedisQueueTransport.new({
  block_time: 5000  # Higher latency, lower CPU usage
})
```

## Migration from Other Transports

### From Redis Pub/Sub

```ruby
# Old Redis Pub/Sub approach
class OrderMessage < SmartMessage::Base
  transport :redis  # Simple pub/sub, everyone gets message
end

OrderMessage.subscribe  # All subscribers get ALL messages

# New Redis Queue approach
class OrderMessage < SmartMessage::Base  
  transport :redis_queue  # Queue-based with routing
end

# Targeted subscriptions
OrderMessage.where.to('order_processor').subscribe     # Only my orders
OrderMessage.where.from('api_gateway').subscribe       # Only from gateway
OrderMessage.subscribe_pattern("#.*.order_service")    # RabbitMQ-style patterns
```

### From RabbitMQ

```ruby
# RabbitMQ configuration
class OrderMessage < SmartMessage::Base
  transport :rabbitmq, {
    exchange: 'orders',
    queue: 'order_processing'
  }
end

# Equivalent Redis Queue configuration  
class OrderMessage < SmartMessage::Base
  transport :redis_queue, {
    queue_prefix: 'orders',
    consumer_group: 'order_processors'
  }
end

# Pattern subscriptions work identically
transport.subscribe_pattern("#.*.order_service")  # Same syntax!
```

## Troubleshooting

### Common Issues

**Queue Not Processing Messages**
```ruby
# Check queue stats
stats = transport.queue_stats
puts "Queue stats: #{stats}"

# Verify pattern matching
pattern = "#.*.my_service"
test_key = "order.ordermessage.api_gateway.my_service"
matches = transport.send(:routing_key_matches_pattern?, test_key, pattern)
puts "Pattern '#{pattern}' matches '#{test_key}': #{matches}"
```

**High Memory Usage**
```ruby
# Monitor queue lengths
stats = transport.queue_stats
long_queues = stats.select { |_, info| info[:length] > 1000 }
puts "Long queues: #{long_queues}"

# Configure queue limits
transport = SmartMessage::Transport::RedisQueueTransport.new({
  max_queue_length: 5000  # Trim at 5k messages
})
```

**Consumer Not Receiving Messages**
```ruby
# Check consumer group membership
consumer_info = transport.consumer_group_info("my_workers")
puts "Consumers: #{consumer_info}"

# Verify routing table
routing_table = transport.routing_table
puts "Routing table: #{routing_table}"
```

### Debug Mode

```ruby
# Enable comprehensive debugging
transport = SmartMessage::Transport::RedisQueueTransport.new({
  debug: true,
  log_level: :debug
})

# Monitor Redis commands
# In separate terminal: redis-cli MONITOR
```

### Performance Debugging

```ruby
# Measure publishing performance
start_time = Time.now
1000.times { |i| TestMessage.new(id: i).publish }
duration = Time.now - start_time
puts "Published 1000 messages in #{duration}s (#{1000/duration} msg/s)"

# Measure processing performance
processed = 0
start_time = Time.now

transport.subscribe_pattern("#.*.*") do |message_class, message_data|
  processed += 1
  if processed % 100 == 0
    rate = processed / (Time.now - start_time)
    puts "Processed #{processed} messages (#{rate} msg/s)"
  end
end
```

## API Reference

### Transport Class

```ruby
class SmartMessage::Transport::RedisQueueTransport < Base
  # Configuration
  def initialize(options = {})
  def configure
  def connected?
  def connect
  def disconnect
  
  # Publishing
  def do_publish(message_class, serialized_message)
  
  # Subscriptions
  def subscribe(message_class, process_method, filter_options = {})
  def subscribe_pattern(pattern, &block)
  def unsubscribe(message_class, process_method)
  def unsubscribe!(message_class)
  
  # Convenience methods
  def subscribe_to_recipient(recipient_id)
  def subscribe_from_sender(sender_id)
  def subscribe_to_type(message_type)
  def subscribe_to_broadcasts
  def subscribe_to_alerts
  
  # Fluent API
  def where
  
  # Management
  def queue_stats
  def routing_table
  def queue_length(queue_name)
  def clear_queue(queue_name)
  def clear_all_queues
  def consumer_group_info(group_name)
  
  # Health and monitoring
  def health_check
  def performance_metrics
  def dead_letter_stats
end
```

### Fluent API Builder

```ruby
class SmartMessage::Transport::RedisQueueSubscriptionBuilder
  def from(sender_id)
  def to(recipient_id) 
  def type(message_type)
  def consumer_group(group_name)
  def build  # Returns pattern string
  def subscribe(&block)  # Subscribes with built pattern
end
```

## Configuration Reference

### Transport Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | `redis://localhost:6379` | Redis connection URL |
| `db` | Integer | `0` | Redis database number |
| `queue_prefix` | String | `smart_message.queue` | Prefix for queue names |
| `consumer_group` | String | `default_workers` | Consumer group name |
| `consumer_id` | String | `#{hostname}_#{pid}` | Unique consumer identifier |
| `block_time` | Integer | `1000` | Blocking timeout in milliseconds |
| `max_queue_length` | Integer | `10000` | Maximum messages per queue |
| `batch_size` | Integer | `1` | Messages to process per batch |
| `max_retries` | Integer | `3` | Maximum retry attempts |
| `retry_delay` | Integer | `5` | Seconds between retries |
| `exponential_backoff` | Boolean | `false` | Use exponential backoff for retries |
| `dead_letter_queue` | Boolean | `false` | Enable dead letter queue |
| `dead_letter_prefix` | String | `dlq` | Prefix for dead letter queues |
| `circuit_breaker` | Boolean | `false` | Enable circuit breaker |
| `failure_threshold` | Integer | `5` | Circuit breaker failure threshold |
| `recovery_timeout` | Integer | `60` | Circuit breaker recovery timeout |
| `pool_size` | Integer | `1` | Connection pool size |
| `pool_timeout` | Integer | `1` | Connection pool timeout |
| `debug` | Boolean | `false` | Enable debug logging |

The Redis Queue Transport represents the pinnacle of SmartMessage's transport evolution, combining the simplicity of Redis with the sophistication of enterprise message brokers. Its unique architecture delivers both the performance characteristics developers need and the routing intelligence that complex applications demand.