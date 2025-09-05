# Redis Queue Transport - Getting Started

This guide will help you get started with SmartMessage's Redis Queue Transport, the most advanced transport offering RabbitMQ-style routing with Redis performance.

## Prerequisites

- Ruby 2.7 or higher
- Redis server running (localhost:6379 by default)
- SmartMessage gem installed

## Installation

Add SmartMessage to your Gemfile:

```ruby
gem 'smart_message', '~> 0.1.0'
```

Or install directly:

```bash
gem install smart_message
```

Ensure Redis is running:

```bash
# Start Redis server
redis-server

# Test Redis connection
redis-cli ping
# Should return: PONG
```

## Quick Start

### 1. Basic Configuration

```ruby
require 'smart_message'

# Configure SmartMessage to use Redis Queue transport
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: 'redis://localhost:6379',
    db: 0,
    queue_prefix: 'myapp_queues',
    consumer_group: 'myapp_workers'
  }
end
```

### 2. Create Your First Message

```ruby
class WelcomeMessage < SmartMessage::Base
  transport :redis_queue
  
  property :user_name, required: true
  property :email, required: true
  property :signup_date, default: -> { Time.now.strftime('%Y-%m-%d') }
  
  def process
    puts "👋 Welcome #{user_name} (#{email})! Signed up: #{signup_date}"
    
    # Your business logic here
    UserMailer.welcome_email(email, user_name).deliver_now
  end
end
```

### 3. Subscribe to Messages

```ruby
# Subscribe to all WelcomeMessage instances
WelcomeMessage.subscribe

puts "✅ Subscribed to welcome messages. Waiting for messages..."

# Keep the script running
sleep
```

### 4. Publish Messages

```ruby
# In another script or Rails console:
WelcomeMessage.new(
  user_name: 'Alice Johnson',
  email: 'alice@example.com'
).publish

puts "📤 Welcome message sent!"
```

## Understanding the Basics

### What Makes Redis Queue Different?

Unlike traditional Redis pub/sub, Redis Queue Transport provides:

1. **Persistent Queues**: Messages survive service restarts
2. **Load Balancing**: Multiple workers share message processing  
3. **Pattern Routing**: Intelligent message routing like RabbitMQ
4. **Queue Management**: Monitor and manage message queues

### Routing Keys

Every message gets an enhanced routing key:

```
namespace.message_type.from_uuid.to_uuid
```

For example:
- `myapp.welcomemessage.signup_service.email_service`
- `myapp.ordermessage.api_gateway.payment_service`

## Basic Patterns

### 1. Simple Producer-Consumer

**Producer:**
```ruby
class TaskMessage < SmartMessage::Base
  transport :redis_queue
  
  property :task_id, required: true
  property :task_type, required: true
  property :priority, default: 'normal'
  
  def process
    puts "⚙️ Processing task #{task_id} [#{task_type}] - Priority: #{priority}"
    
    # Simulate work
    sleep(rand(1..3))
    
    puts "✅ Task #{task_id} completed!"
  end
end

# Publish tasks
5.times do |i|
  TaskMessage.new(
    task_id: "TASK-#{sprintf('%03d', i + 1)}",
    task_type: ['import', 'export', 'backup', 'cleanup', 'report'][i],
    priority: ['low', 'normal', 'high'][rand(3)]
  ).publish
end
```

**Consumer:**
```ruby
# Start processing tasks
TaskMessage.subscribe

puts "🔧 Task processor started. Waiting for tasks..."
sleep  # Keep running
```

### 2. Multiple Services Communication

**User Service:**
```ruby
class UserCreated < SmartMessage::Base
  transport :redis_queue
  
  property :user_id, required: true
  property :name, required: true
  property :email, required: true
  
  def process
    puts "👤 User created: #{name} (#{email})"
  end
end

# Simulate user creation
User.after_create do |user|
  UserCreated.new(
    user_id: user.id,
    name: user.name,
    email: user.email,
    _sm_header: {
      from: 'user_service',
      to: 'notification_service'
    }
  ).publish
end
```

**Notification Service:**
```ruby
# Create transport for pattern subscription
transport = SmartMessage::Transport::RedisQueueTransport.new(
  queue_prefix: 'notifications',
  consumer_group: 'notification_workers'
)

# Subscribe to messages directed to notification service
transport.subscribe_pattern("#.*.notification_service") do |message_class, message_data|
  data = JSON.parse(message_data)
  
  puts "📧 Notification service received: #{message_class}"
  puts "   User: #{data['name']} (#{data['email']})"
  
  # Send welcome email
  WelcomeMailer.send_email(data['email'], data['name'])
end

puts "📧 Notification service started. Waiting for user events..."
sleep
```

### 3. Load Balancing Workers

**Setup Multiple Workers:**
```ruby
# worker1.rb
class ProcessingTask < SmartMessage::Base
  transport :redis_queue, {
    consumer_group: 'processing_workers'
  }
  
  property :data, required: true
  
  def process
    worker_id = Thread.current.object_id.to_s[-4..-1]
    puts "⚙️ Worker-#{worker_id} processing: #{data}"
    
    # Simulate work
    sleep(rand(0.5..2.0))
    
    puts "✅ Worker-#{worker_id} completed: #{data}"
  end
end

ProcessingTask.subscribe
puts "🔧 Worker 1 started"
sleep
```

```ruby
# worker2.rb (identical code, different process)
# worker3.rb (identical code, different process)
```

**Send Work:**
```ruby
# Send tasks that will be load balanced
20.times do |i|
  ProcessingTask.new(
    data: "Task #{i + 1}",
    _sm_header: {
      from: 'task_scheduler',
      to: 'worker_pool'
    }
  ).publish
end

puts "📤 Sent 20 tasks to worker pool"
```

## Pattern-Based Routing

### Basic Patterns

```ruby
transport = SmartMessage::Transport::RedisQueueTransport.new

# Messages TO specific service
transport.subscribe_pattern("#.*.payment_service") do |msg_class, data|
  puts "💳 Payment service: #{msg_class}"
end

# Messages FROM specific service  
transport.subscribe_pattern("#.api_gateway.*") do |msg_class, data|
  puts "🌐 From API Gateway: #{msg_class}"
end

# Specific message types
transport.subscribe_pattern("order.#.*.*") do |msg_class, data|
  puts "📦 Order message: #{msg_class}"
end

# Broadcast messages
transport.subscribe_pattern("#.*.broadcast") do |msg_class, data|
  puts "📢 Broadcast: #{msg_class}"
end
```

### Wildcard Examples

| Pattern | Matches | Example |
|---------|---------|---------|
| `#.*.my_service` | All messages TO my_service | `order.ordermessage.api.my_service` |
| `#.admin.*` | All messages FROM admin | `user.usercreated.admin.notification` |
| `order.#.*.*` | All order messages | `order.ordercreated.api.payment` |
| `*.*.*.broadcast` | All broadcasts | `alert.systemalert.monitor.broadcast` |
| `#.#.#.urgent` | All urgent messages | `emergency.alert.security.urgent` |

## Fluent API

The fluent API provides an expressive way to build subscriptions:

```ruby
transport = SmartMessage::Transport::RedisQueueTransport.new

# Simple fluent subscriptions
transport.where
  .from('api_service')
  .subscribe { |msg, data| puts "From API: #{msg}" }

transport.where
  .to('my_service')
  .subscribe { |msg, data| puts "To Me: #{msg}" }

transport.where
  .type('OrderMessage')
  .subscribe { |msg, data| puts "Order: #{msg}" }

# Combined criteria
transport.where
  .from('web_app')
  .to('analytics_service')
  .subscribe { |msg, data| puts "Web → Analytics: #{msg}" }

# Load balancing
transport.where
  .to('shared_service')
  .consumer_group('shared_workers')
  .subscribe { |msg, data| puts "Shared worker: #{msg}" }
```

## Queue Management

### Monitor Queue Status

```ruby
transport = SmartMessage::Transport::RedisQueueTransport.new

# Get queue statistics
stats = transport.queue_stats
puts "📊 Queue Statistics:"
stats.each do |queue_name, info|
  puts "  #{queue_name}:"
  puts "    Messages: #{info[:length]}"
  puts "    Consumers: #{info[:consumers]}"
  puts "    Pattern: #{info[:pattern]}"
  puts ""
end

# Show routing table
routing_table = transport.routing_table
puts "🗺️ Routing Table:"
routing_table.each do |pattern, queues|
  puts "  '#{pattern}' → #{queues.join(', ')}"
end
```

### Health Monitoring

```ruby
def monitor_queues(transport)
  stats = transport.queue_stats
  
  # Check for problems
  problems = []
  
  stats.each do |queue, info|
    if info[:length] > 100
      problems << "⚠️ High load: #{queue} has #{info[:length]} messages"
    elsif info[:length] > 0 && info[:consumers] == 0
      problems << "🔴 No consumers: #{queue} has #{info[:length]} pending messages"
    end
  end
  
  if problems.any?
    puts "Queue Issues:"
    problems.each { |problem| puts "  #{problem}" }
  else
    puts "✅ All queues healthy"
  end
end

# Monitor periodically
loop do
  monitor_queues(transport)
  sleep 30
end
```

## Production Configuration

### Environment-Specific Settings

```ruby
# config/environments/development.rb
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: 'redis://localhost:6379',
    db: 15,  # Use test database
    queue_prefix: 'myapp_dev',
    consumer_group: 'dev_workers',
    block_time: 1000,  # 1 second for quick debugging
    debug: true
  }
end

# config/environments/production.rb
SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: ENV['REDIS_URL'] || 'redis://redis.prod.company.com:6379',
    db: 0,
    queue_prefix: 'myapp_prod',
    consumer_group: 'prod_workers',
    block_time: 5000,  # 5 seconds for efficiency
    max_queue_length: 50000,  # Large queues
    max_retries: 3,
    dead_letter_queue: true,
    pool_size: 10  # Connection pooling
  }
end
```

### Worker Configuration

```ruby
# config/workers.rb
class ApplicationWorker
  def self.start
    # Start multiple worker types
    start_order_workers(3)      # 3 order processing workers
    start_email_workers(2)      # 2 email workers  
    start_report_workers(1)     # 1 report worker
    start_general_workers(5)    # 5 general purpose workers
  end
  
  def self.start_order_workers(count)
    count.times do |i|
      Thread.new do
        transport = SmartMessage::Transport::RedisQueueTransport.new(
          consumer_group: 'order_workers',
          consumer_id: "order_worker_#{i + 1}"
        )
        
        transport.where
          .to('order_service')
          .consumer_group('order_workers')
          .subscribe { |msg, data| puts "Order Worker #{i + 1}: #{msg}" }
      end
    end
  end
  
  # Similar methods for other worker types...
end

# Start all workers
ApplicationWorker.start
```

### Health Checks

```ruby
# lib/health_check.rb
class RedisQueueHealthCheck
  def self.check
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    begin
      # Test connectivity
      connected = transport.connected?
      
      # Check queue health
      stats = transport.queue_stats
      queue_issues = stats.select { |_, info| info[:length] > 1000 || (info[:length] > 0 && info[:consumers] == 0) }
      
      {
        status: connected && queue_issues.empty? ? 'healthy' : 'unhealthy',
        connected: connected,
        total_queues: stats.size,
        total_messages: stats.values.sum { |info| info[:length] },
        total_consumers: stats.values.sum { |info| info[:consumers] || 0 },
        queue_issues: queue_issues
      }
    rescue => e
      {
        status: 'error',
        error: e.message
      }
    ensure
      transport.disconnect
    end
  end
end

# Use in Rails health check endpoint
class HealthController < ApplicationController
  def show
    health_info = RedisQueueHealthCheck.check
    
    if health_info[:status] == 'healthy'
      render json: health_info, status: :ok
    else
      render json: health_info, status: :service_unavailable
    end
  end
end
```

## Common Patterns and Best Practices

### 1. Request-Response Pattern

```ruby
# Request message
class ProcessingRequest < SmartMessage::Base
  transport :redis_queue
  
  property :request_id, required: true
  property :data, required: true
  property :callback_service, required: true
  
  def process
    # Process the request
    result = process_data(data)
    
    # Send response back
    ProcessingResponse.new(
      request_id: request_id,
      result: result,
      status: 'success',
      _sm_header: {
        from: 'processing_service',
        to: callback_service
      }
    ).publish
  end
end

# Response message
class ProcessingResponse < SmartMessage::Base
  transport :redis_queue
  
  property :request_id, required: true
  property :result, required: true
  property :status, required: true
  
  def process
    puts "📥 Response for request #{request_id}: #{status}"
    # Handle response
  end
end
```

### 2. Saga Pattern

```ruby
class OrderSaga
  def self.start_order(order_data)
    # Step 1: Reserve inventory
    ReserveInventory.new(
      saga_id: order_data[:saga_id],
      order_id: order_data[:order_id],
      items: order_data[:items],
      _sm_header: { from: 'order_saga', to: 'inventory_service' }
    ).publish
  end
end

class ReserveInventory < SmartMessage::Base
  transport :redis_queue
  
  def process
    if inventory_available?
      # Success - continue saga
      ProcessPayment.new(
        saga_id: saga_id,
        order_id: order_id,
        amount: calculate_amount,
        _sm_header: { from: 'inventory_service', to: 'payment_service' }
      ).publish
    else
      # Failure - compensate
      OrderFailed.new(
        saga_id: saga_id,
        reason: 'Inventory not available',
        _sm_header: { from: 'inventory_service', to: 'order_saga' }
      ).publish
    end
  end
end
```

### 3. Event Sourcing

```ruby
class EventStore
  def self.append_event(event)
    EventAppended.new(
      event_id: SecureRandom.uuid,
      event_type: event.class.name,
      event_data: event.to_h,
      timestamp: Time.now,
      _sm_header: { from: 'event_store', to: 'broadcast' }
    ).publish
  end
end

# Projections subscribe to events
class OrderProjection < SmartMessage::Base
  transport :redis_queue
  
  def self.subscribe_to_events
    transport = SmartMessage::Transport::RedisQueueTransport.new
    
    transport.subscribe_pattern("event.#.*.*") do |msg_class, data|
      event = JSON.parse(data)
      
      case event['event_type']
      when 'OrderCreated'
        update_order_projection(event['event_data'])
      when 'OrderCancelled'
        cancel_order_projection(event['event_data'])
      end
    end
  end
end
```

## Troubleshooting

### Debug Mode

```ruby
# Enable detailed logging
transport = SmartMessage::Transport::RedisQueueTransport.new(
  debug: true,
  log_level: :debug
)

# Or set environment variable
ENV['SMART_MESSAGE_DEBUG'] = 'true'
```

### Common Issues

**Messages not being processed:**
```ruby
# Check if anyone is subscribed
stats = transport.queue_stats
stats.each do |queue, info|
  if info[:length] > 0 && info[:consumers] == 0
    puts "No consumers for #{queue}"
  end
end
```

**Pattern not matching:**
```ruby
# Test pattern matching
transport = SmartMessage::Transport::RedisQueueTransport.new
pattern = "#.*.my_service"
test_key = "order.ordermessage.api.my_service"

# This uses private method for testing
matches = transport.send(:routing_key_matches_pattern?, test_key, pattern)
puts "Pattern matches: #{matches}"
```

**High memory usage:**
```ruby
# Check for large queues
stats = transport.queue_stats
large_queues = stats.select { |_, info| info[:length] > 1000 }
puts "Large queues: #{large_queues}"

# Configure queue limits
transport = SmartMessage::Transport::RedisQueueTransport.new(
  max_queue_length: 5000
)
```

## Next Steps

Now that you understand the basics, explore these advanced topics:

1. **[Advanced Routing Patterns](redis-queue-patterns.md)** - Complex routing scenarios
2. **[Production Deployment](redis-queue-production.md)** - Production-ready configurations
3. **[Complete Transport Reference](../transports/redis-queue.md)** - Full API documentation

Or dive into the [complete examples](../examples/redis_queue/) to see real-world usage patterns.

The Redis Queue Transport provides the perfect balance of performance, reliability, and intelligent routing for modern Ruby applications. Start with these patterns and gradually incorporate more advanced features as your needs grow.