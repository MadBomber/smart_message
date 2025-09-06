# Examples & Use Cases

This document provides practical examples of using SmartMessage in real-world scenarios.

## Basic Messaging Patterns

### Simple Notification System

```ruby
require 'smart_message'

class NotificationMessage < SmartMessage::Base
  description "Sends notifications to users via multiple channels"
  
  property :recipient
  property :subject
  property :body
  property :priority, default: 'normal'
  property :channel, default: 'email'

  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    notification = decoded_message
    
    case notification.channel
    when 'email'
      send_email(notification)
    when 'sms'
      send_sms(notification)
    when 'push'
      send_push_notification(notification)
    end
  end

  private

  def self.send_email(notification)
    puts "📧 Sending email to #{notification.recipient}"
    puts "Subject: #{notification.subject}"
    puts "Priority: #{notification.priority}"
  end

  def self.send_sms(notification)
    puts "📱 Sending SMS to #{notification.recipient}"
    puts "Message: #{notification.body}"
  end

  def self.send_push_notification(notification)
    puts "🔔 Sending push notification to #{notification.recipient}"
    puts "Title: #{notification.subject}"
  end
end

# Setup
NotificationMessage.subscribe

# Send notifications
NotificationMessage.new(
  recipient: "user@example.com",
  subject: "Welcome!",
  body: "Thanks for signing up!",
  priority: "high"
).publish

NotificationMessage.new(
  recipient: "+1234567890",
  subject: "Alert",
  body: "Your order has shipped!",
  channel: "sms"
).publish
```

### Event-Driven Architecture

```ruby
# User registration event
class UserRegisteredEvent < SmartMessage::Base
  property :user_id
  property :email
  property :name
  property :registration_source
  property :timestamp, default: -> { Time.now.iso8601 }

  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    event = decoded_message
    
    # Fan out to multiple handlers
    send_welcome_email(event)
    create_user_profile(event)
    track_analytics(event)
    setup_default_preferences(event)
  end

  private

  def self.send_welcome_email(event)
    WelcomeEmailMessage.new(
      user_id: event.user_id,
      email: event.email,
      name: event.name
    ).publish
  end

  def self.create_user_profile(event)
    CreateProfileMessage.new(
      user_id: event.user_id,
      source: event.registration_source
    ).publish
  end

  def self.track_analytics(event)
    AnalyticsMessage.new(
      event_type: 'user_registration',
      user_id: event.user_id,
      properties: {
        source: event.registration_source,
        timestamp: event.timestamp
      }
    ).publish
  end

  def self.setup_default_preferences(event)
    PreferencesMessage.new(
      user_id: event.user_id,
      preferences: default_preferences
    ).publish
  end

  def self.default_preferences
    {
      email_notifications: true,
      marketing_emails: false,
      theme: 'light'
    }
  end
end

# Supporting message classes
class WelcomeEmailMessage < SmartMessage::Base
  property :user_id
  property :email
  property :name

  config do
    transport SmartMessage::Transport.create(:stdout)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    message = decoded_message
    
    puts "📧 Sending welcome email to #{message.email} (#{message.name})"
    # Email sending logic here
  end
end

class AnalyticsMessage < SmartMessage::Base
  property :event_type
  property :user_id
  property :properties

  config do
    transport SmartMessage::Transport.create(:stdout)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    event = decoded_message
    
    puts "📊 Tracking event: #{event.event_type} for user #{event.user_id}"
    # Analytics tracking logic here
  end
end

# Setup and trigger
[UserRegisteredEvent, WelcomeEmailMessage, AnalyticsMessage].each(&:subscribe)

# Simulate user registration
UserRegisteredEvent.new(
  user_id: 12345,
  email: "alice@example.com",
  name: "Alice Johnson",
  registration_source: "web_form"
).publish
```

## E-commerce Order Processing

```ruby
# Order lifecycle management
class OrderCreatedMessage < SmartMessage::Base
  property :order_id
  property :customer_id
  property :items
  property :total_amount
  property :shipping_address
  property :created_at, default: -> { Time.now.iso8601 }

  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    order = decoded_message
    
    # Validate order
    if valid_order?(order)
      # Reserve inventory
      InventoryReservationMessage.new(
        order_id: order.order_id,
        items: order.items
      ).publish
      
      # Process payment
      PaymentProcessingMessage.new(
        order_id: order.order_id,
        customer_id: order.customer_id,
        amount: order.total_amount
      ).publish
    else
      # Handle invalid order
      OrderRejectedMessage.new(
        order_id: order.order_id,
        reason: "Invalid order data"
      ).publish
    end
  end

  private

  def self.valid_order?(order)
    order.items&.any? && order.total_amount&.positive?
  end
end

class InventoryReservationMessage < SmartMessage::Base
  property :order_id
  property :items

  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    reservation = decoded_message
    
    success = reserve_inventory(reservation.items)
    
    if success
      InventoryReservedMessage.new(
        order_id: reservation.order_id
      ).publish
    else
      InventoryFailedMessage.new(
        order_id: reservation.order_id,
        reason: "Insufficient stock"
      ).publish
    end
  end

  private

  def self.reserve_inventory(items)
    # Inventory reservation logic
    puts "🏪 Reserving inventory for #{items.length} items"
    true  # Simulate success
  end
end

class PaymentProcessingMessage < SmartMessage::Base
  property :order_id
  property :customer_id
  property :amount

  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    payment = decoded_message
    
    success = process_payment(payment)
    
    if success
      PaymentSuccessMessage.new(
        order_id: payment.order_id,
        transaction_id: generate_transaction_id
      ).publish
    else
      PaymentFailedMessage.new(
        order_id: payment.order_id,
        reason: "Payment declined"
      ).publish
    end
  end

  private

  def self.process_payment(payment)
    puts "💳 Processing payment of $#{payment.amount} for order #{payment.order_id}"
    true  # Simulate success
  end

  def self.generate_transaction_id
    "txn_#{SecureRandom.hex(8)}"
  end
end

# Setup
[
  OrderCreatedMessage,
  InventoryReservationMessage, 
  PaymentProcessingMessage
].each(&:subscribe)

# Create an order
OrderCreatedMessage.new(
  order_id: "ORD-001",
  customer_id: "CUST-123",
  items: [
    { sku: "WIDGET-A", quantity: 2, price: 19.99 },
    { sku: "GADGET-B", quantity: 1, price: 49.99 }
  ],
  total_amount: 89.97,
  shipping_address: {
    street: "123 Main St",
    city: "Anytown",
    state: "CA",
    zip: "12345"
  }
).publish
```

## Logging and Monitoring

```ruby
# Centralized logging system
class LogMessage < SmartMessage::Base
  property :level
  property :service
  property :message
  property :context
  property :timestamp, default: -> { Time.now.iso8601 }
  property :correlation_id

  config do
    transport SmartMessage::Transport.create(:stdout, output: "application.log")
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    log_entry = decoded_message
    
    formatted_message = format_log_entry(log_entry)
    
    case log_entry.level
    when 'ERROR', 'FATAL'
      send_alert(log_entry)
    when 'WARN'
      track_warning(log_entry)
    end
    
    puts formatted_message
  end

  private

  def self.format_log_entry(log_entry)
    "[#{log_entry.timestamp}] #{log_entry.level} #{log_entry.service}: #{log_entry.message}" +
    (log_entry.correlation_id ? " (#{log_entry.correlation_id})" : "") +
    (log_entry.context ? " | #{log_entry.context.to_json}" : "")
  end

  def self.send_alert(log_entry)
    if log_entry.level == 'FATAL'
      puts "🚨 FATAL ERROR ALERT: #{log_entry.message}"
    else
      puts "⚠️  ERROR ALERT: #{log_entry.message}"
    end
  end

  def self.track_warning(log_entry)
    puts "📝 Warning tracked: #{log_entry.message}"
  end
end

# Application performance monitoring
class MetricMessage < SmartMessage::Base
  property :metric_name
  property :value
  property :unit
  property :tags
  property :timestamp, default: -> { Time.now.to_f }

  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    metric = decoded_message
    
    # Store metric (would typically go to monitoring system)
    store_metric(metric)
    
    # Check for alerts
    check_thresholds(metric)
  end

  private

  def self.store_metric(metric)
    puts "📊 Metric: #{metric.metric_name} = #{metric.value} #{metric.unit} #{metric.tags}"
  end

  def self.check_thresholds(metric)
    case metric.metric_name
    when 'response_time'
      if metric.value > 1000  # More than 1 second
        puts "⚠️  High response time alert: #{metric.value}ms"
      end
    when 'error_rate'
      if metric.value > 0.05  # More than 5% error rate
        puts "🚨 High error rate alert: #{(metric.value * 100).round(2)}%"
      end
    end
  end
end

# Setup
LogMessage.subscribe
MetricMessage.subscribe

# Log some events
LogMessage.new(
  level: "INFO",
  service: "user-service",
  message: "User login successful",
  context: { user_id: 123, ip: "192.168.1.1" },
  correlation_id: "req-abc123"
).publish

LogMessage.new(
  level: "ERROR",
  service: "payment-service",
  message: "Payment gateway timeout",
  context: { order_id: "ORD-001", gateway: "stripe" },
  correlation_id: "req-def456"
).publish

# Send some metrics
MetricMessage.new(
  metric_name: "response_time",
  value: 1250,
  unit: "ms",
  tags: { service: "api", endpoint: "/users" }
).publish

MetricMessage.new(
  metric_name: "error_rate",
  value: 0.08,
  unit: "percentage",
  tags: { service: "payment-service" }
).publish
```

## Gateway Pattern

```ruby
# Bridge between different message systems
class MessageGateway < SmartMessage::Base
  property :source_system
  property :destination_system
  property :message_type
  property :payload

  # Receive from one transport
  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    gateway_message = decoded_message
    
    # Transform and forward to destination system
    case gateway_message.destination_system
    when 'email_system'
      forward_to_email_system(gateway_message)
    when 'sms_system'
      forward_to_sms_system(gateway_message)
    when 'audit_system'
      forward_to_audit_system(gateway_message)
    end
  end

  private

  def self.forward_to_email_system(gateway_message)
    # Create a new message instance with different transport
    email_message = EmailSystemMessage.new(
      original_payload: gateway_message.payload,
      source: gateway_message.source_system
    )
    
    # Override transport for this instance
    email_message.config do
      transport SmartMessage::Transport.create(:stdout, output: "email_system.log")
    end
    
    email_message.publish
  end

  def self.forward_to_sms_system(gateway_message)
    sms_message = SMSSystemMessage.new(
      original_payload: gateway_message.payload,
      source: gateway_message.source_system
    )
    
    sms_message.config do
      transport SmartMessage::Transport.create(:stdout, output: "sms_system.log")
    end
    
    sms_message.publish
  end

  def self.forward_to_audit_system(gateway_message)
    audit_message = AuditSystemMessage.new(
      event_type: gateway_message.message_type,
      data: gateway_message.payload,
      source_system: gateway_message.source_system,
      processed_at: Time.now.iso8601
    )
    
    audit_message.config do
      transport SmartMessage::Transport.create(:stdout, output: "audit_system.log")
    end
    
    audit_message.publish
  end
end

# Destination system message classes
class EmailSystemMessage < SmartMessage::Base
  property :original_payload
  property :source

  def self.process(decoded_message)
    puts "📧 Email system processed message from #{decoded_message.source}"
  end
end

class SMSSystemMessage < SmartMessage::Base
  property :original_payload
  property :source

  def self.process(decoded_message)
    puts "📱 SMS system processed message from #{decoded_message.source}"
  end
end

class AuditSystemMessage < SmartMessage::Base
  property :event_type
  property :data
  property :source_system
  property :processed_at

  def self.process(decoded_message)
    puts "📋 Audit system logged event from #{decoded_message.source_system}"
  end
end

# Setup
[MessageGateway, EmailSystemMessage, SMSSystemMessage, AuditSystemMessage].each(&:subscribe)

# Route messages through gateway
MessageGateway.new(
  source_system: "web_app",
  destination_system: "email_system",
  message_type: "notification",
  payload: { recipient: "user@example.com", subject: "Hello!" }
).publish

MessageGateway.new(
  source_system: "mobile_app",
  destination_system: "audit_system",
  message_type: "user_action",
  payload: { action: "login", user_id: 123 }
).publish
```

## Error Handling and Retry Patterns

```ruby
# Resilient message processing with retries
class ResilientMessage < SmartMessage::Base
  property :data
  property :retry_count, default: 0
  property :max_retries, default: 3
  property :original_error

  config do
    transport SmartMessage::Transport.create(:memory, auto_process: true)
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    message = decoded_message
    
    begin
      # Simulate potentially failing operation
      if should_fail?(message)
        raise StandardError, "Simulated failure"
      end
      
      puts "✅ Successfully processed message: #{message.data}"
      
    rescue => e
      handle_error(message, e)
    end
  end

  private

  def self.should_fail?(message)
    # Simulate 30% failure rate
    rand < 0.3
  end

  def self.handle_error(message, error)
    puts "❌ Error processing message: #{error.message}"
    
    if message.retry_count < message.max_retries
      # Retry with exponential backoff
      delay = 2 ** message.retry_count
      puts "🔄 Retrying in #{delay} seconds (attempt #{message.retry_count + 1})"
      
      # In a real system, you'd use a delayed job or similar
      Thread.new do
        sleep(delay)
        
        retry_message = new(
          data: message.data,
          retry_count: message.retry_count + 1,
          max_retries: message.max_retries,
          original_error: error.message
        )
        
        retry_message.publish
      end
    else
      # Max retries exceeded, send to dead letter queue
      DeadLetterMessage.new(
        original_message: message.to_h,
        final_error: error.message,
        retry_attempts: message.retry_count,
        failed_at: Time.now.iso8601
      ).publish
    end
  end
end

class DeadLetterMessage < SmartMessage::Base
  property :original_message
  property :final_error
  property :retry_attempts
  property :failed_at

  config do
    transport SmartMessage::Transport.create(:stdout, output: "dead_letter_queue.log")
    serializer SmartMessage::Serializer::Json.new
  end

  def self.process(decoded_message)
    # decoded_message is already a message instance
    dead_letter = decoded_message
    
    puts "💀 Message sent to dead letter queue:"
    puts "   Original: #{dead_letter.original_message}"
    puts "   Error: #{dead_letter.final_error}"
    puts "   Attempts: #{dead_letter.retry_attempts}"
    puts "   Failed at: #{dead_letter.failed_at}"
    
    # Could trigger alerts, save to database, etc.
  end
end

# Setup
ResilientMessage.subscribe
DeadLetterMessage.subscribe

# Send messages that might fail
5.times do |i|
  ResilientMessage.new(
    data: "Test message #{i + 1}"
  ).publish
  
  sleep(0.1)  # Small delay between messages
end
```

## Testing Helpers

```ruby
# Test utilities for SmartMessage
module SmartMessageTestHelpers
  def self.with_test_transport
    original_transports = {}
    
    # Store original transports
    SmartMessage::Base.descendants.each do |klass|
      original_transports[klass] = klass.transport
    end
    
    # Set up test transport
    test_transport = SmartMessage::Transport.create(:memory, auto_process: true)
    
    SmartMessage::Base.descendants.each do |klass|
      klass.config do
        transport test_transport
      end
    end
    
    yield test_transport
    
  ensure
    # Restore original transports
    original_transports.each do |klass, transport|
      klass.config do
        transport transport
      end
    end
  end
  
  def self.clear_statistics
    SS.reset
  end
  
  def self.wait_for_processing(timeout: 1.0)
    start_time = Time.now
    
    while Time.now - start_time < timeout
      # Check if any messages are still being processed
      # This is a simplified check
      sleep(0.01)
    end
  end
end

# Example test usage
def test_message_processing
  SmartMessageTestHelpers.with_test_transport do |transport|
    # Clear any existing messages
    transport.clear_messages
    SmartMessageTestHelpers.clear_statistics
    
    # Set up subscriptions
    TestMessage.subscribe
    
    # Send test message
    TestMessage.new(data: "test").publish
    
    # Wait for processing
    SmartMessageTestHelpers.wait_for_processing
    
    # Check results
    puts "Messages in transport: #{transport.message_count}"
    puts "Published count: #{SS.get('TestMessage', 'publish')}"
    puts "Processed count: #{SS.get('TestMessage', 'TestMessage.process', 'routed')}"
  end
end

class TestMessage < SmartMessage::Base
  property :data
  
  def self.process(decoded_message)
    # decoded_message is already a message instance
    message = decoded_message
    puts "Processed test message: #{message.data}"
  end
end

# Run the test
test_message_processing
```

These examples demonstrate the flexibility and power of SmartMessage for building robust, scalable messaging systems. Each pattern can be adapted to your specific needs and combined with other patterns for more complex workflows.

## Executable Example Programs

The `examples/` directory contains complete, runnable programs that demonstrate various SmartMessage features:

### Memory Transport Examples
- **`memory/03_point_to_point_orders.rb`** - Point-to-point order processing with payment integration
- **`memory/04_publish_subscribe_events.rb`** - Event broadcasting to multiple services (email, SMS, audit)
- **`memory/05_many_to_many_chat.rb`** - Interactive chat system with rooms, bots, and human agents
- **`memory/07_proc_handlers_demo.rb`** - Flexible message handlers (blocks, procs, lambdas, methods)
- **`memory/08_custom_logger_demo.rb`** - Advanced logging with SmartMessage::Logger::Default
- **`memory/09_error_handling_demo.rb`** - Comprehensive validation, version mismatch, and error handling
- **`memory/10_entity_addressing_basic.rb`** - Basic FROM/TO/REPLY_TO message addressing
- **`memory/11_entity_addressing_with_filtering.rb`** - Advanced entity-aware message filtering
- **`memory/02_dead_letter_queue_demo.rb`** - Complete Dead Letter Queue system demonstration
- **`memory/01_message_deduplication_demo.rb`** - Message deduplication patterns
- **`memory/12_regex_filtering_microservices.rb`** - Advanced regex filtering for microservices
- **`memory/13_header_block_configuration.rb`** - Header and block configuration examples
- **`memory/14_global_configuration_demo.rb`** - Global configuration management
- **`memory/15_logger_demo.rb`** - Advanced logging demonstrations

### Redis Transport Examples
- **`redis/01_smart_home_iot_demo.rb`** - Redis-based IoT sensor monitoring with real-time data flow

### Redis Enhanced Transport Examples
- **`redis_enhanced/enhanced_01_basic_patterns.rb`** - Basic enhanced transport patterns
- **`redis_enhanced/enhanced_02_fluent_api.rb`** - Fluent API usage examples
- **`redis_enhanced/enhanced_03_dual_publishing.rb`** - Dual publishing strategies
- **`redis_enhanced/enhanced_04_advanced_routing.rb`** - Advanced message routing

### Redis Queue Transport Examples
- **`redis_queue/01_basic_messaging.rb`** - Basic queue messaging patterns
- **`redis_queue/02_pattern_routing.rb`** - Pattern-based message routing
- **`redis_queue/03_fluent_api.rb`** - Fluent API for queue operations
- **`redis_queue/04_load_balancing.rb`** - Load balancing across workers
- **`redis_queue/05_microservices.rb`** - Microservices communication
- **`redis_queue/06_emergency_alerts.rb`** - Emergency alert system
- **`redis_queue/07_queue_management.rb`** - Queue management utilities
- **`redis_queue/01_comprehensive_examples.rb`** - Comprehensive feature demonstration

### City Scenario (Comprehensive Demo)
- **`city_scenario/`** - Complete emergency services simulation with multiple services and AI integration

### Performance Testing
- **`performance_metrics/`** - Benchmarking tools and performance comparisons

### Running Examples

```bash
# Navigate to the SmartMessage directory
cd smart_message

# Run examples from their respective transport directories
ruby examples/memory/03_point_to_point_orders.rb
ruby examples/memory/02_dead_letter_queue_demo.rb
ruby examples/redis/01_smart_home_iot_demo.rb
ruby examples/redis_queue/01_basic_messaging.rb

# For city scenario comprehensive demo
cd examples/city_scenario && ./start_demo.sh
```

Each example is self-contained and includes:
- Clear educational comments
- Multiple message classes
- Complete setup and teardown
- Real-world scenarios
- Best practices demonstration

### Example Features Demonstrated

| Example | Transport | Features | Use Case |
|---------|-----------|----------|----------|
| memory/03 | Memory/STDOUT | Point-to-point, validation | Order processing |
| memory/04 | Memory/STDOUT | Pub-sub, multiple handlers | Event broadcasting |
| memory/05 | Memory | Many-to-many, bots | Chat systems |
| redis/01 | Redis | IoT, real-time, addressing | Smart home monitoring |
| memory/07 | Memory | Proc handlers, flexibility | Dynamic message handling |
| memory/08 | Memory/STDOUT | Custom logging, lifecycle | Production logging |
| memory/09 | Memory/STDOUT | Error handling, validation | Robust message systems |
| memory/10-11 | Memory/STDOUT | Entity addressing, filtering | Microservice communication |
| memory/02 | Memory | DLQ, circuit breakers, replay | Production reliability |
| redis_queue/* | Redis Queue | Load balancing, persistence | Production messaging |
| city_scenario/* | Redis | AI integration, health monitoring | Emergency services |

These examples provide practical, working code that you can use as a starting point for your own SmartMessage implementations.