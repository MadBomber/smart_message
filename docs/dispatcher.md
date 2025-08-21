# Dispatcher & Message Routing

The dispatcher is the heart of SmartMessage's message routing system. It manages subscriptions, routes incoming messages to appropriate handlers, and coordinates concurrent processing using thread pools.

## Overview

The dispatcher handles:
- **Subscription Management**: Tracking which classes want to receive which messages
- **Message Routing**: Directing incoming messages to registered handlers
- **Concurrent Processing**: Using thread pools for parallel message processing
- **Statistics Collection**: Tracking message processing metrics
- **Error Isolation**: Preventing individual message failures from affecting the system

## Core Components

### SmartMessage::Dispatcher

Located at `lib/smart_message/dispatcher.rb:11-147`, the dispatcher is the central routing engine.

**Key Features:**
- Thread-safe subscription management
- Concurrent message processing via `Concurrent::CachedThreadPool`
- Automatic thread pool lifecycle management
- Built-in statistics collection
- Graceful shutdown handling

## Subscription Management

### Adding Subscriptions

SmartMessage supports multiple subscription patterns:

```ruby
# 1. Default handler - uses self.process method
MyMessage.subscribe
# Registers "MyMessage.process" as the handler

# 2. Custom method handler
MyMessage.subscribe("MyService.handle_message")
# Registers "MyService.handle_message" as the handler

# 3. Block handler (NEW!)
handler_id = MyMessage.subscribe do |header, payload|
  puts "Processing: #{JSON.parse(payload)}"
end
# Registers a proc handler with generated ID like "MyMessage.proc_abc123"

# 4. Proc handler (NEW!)
my_proc = proc { |header, payload| log_message(payload) }
proc_id = MyMessage.subscribe(my_proc)
# Registers the proc with generated ID

# 5. Lambda handler (NEW!)
my_lambda = lambda { |header, payload| validate_message(payload) }
lambda_id = MyMessage.subscribe(my_lambda)

# Multiple handlers for the same message
MyMessage.subscribe("MyMessage.audit")
MyMessage.subscribe("MyMessage.notify")
MyMessage.subscribe { |h,p| puts "Quick log" }
# All handlers will receive the message
```

### Message Filtering (NEW!)

SmartMessage supports advanced message filtering using exact strings, regular expressions, or arrays for precise message routing:

```ruby
# Basic string filtering (exact match)
MyMessage.subscribe(from: 'payment-service')
MyMessage.subscribe(to: 'order-processor')

# Regular expression filtering
MyMessage.subscribe(from: /^payment-.*/)        # All payment services
MyMessage.subscribe(to: /^(dev|staging)-.*/)    # Development environments

# Array filtering (multiple options)
MyMessage.subscribe(from: ['admin', 'system', 'monitoring'])

# Mixed exact and pattern matching
MyMessage.subscribe(from: ['admin', /^system-.*/, 'legacy-service'])

# Combined filtering
MyMessage.subscribe(
  from: /^admin-.*/, 
  to: ['order-service', /^fulfillment-.*/]
)

# Broadcast + directed filtering
MyMessage.subscribe(broadcast: true, to: 'api-service')
```

#### Filter Types

**String Filters (Exact Match)**
```ruby
# Subscribe only to messages from specific sender
OrderMessage.subscribe(from: 'payment-service')

# Subscribe only to messages directed to specific recipient
OrderMessage.subscribe(to: 'order-processor')
```

**Regular Expression Filters (Pattern Match)**
```ruby
# Environment-based routing
DevService.subscribe(to: /^(dev|staging)-.*/)
ProdService.subscribe(to: /^prod-.*/)

# Service pattern routing
PaymentProcessor.subscribe(from: /^payment-.*/)
ApiService.subscribe(from: /^(web|mobile|api)-.*/)
```

**Array Filters (Multiple Options)**
```ruby
# Multiple specific services
AdminService.subscribe(from: ['admin', 'system', 'monitoring'])

# Mixed patterns and exact matches
AlertService.subscribe(from: ['admin', /^system-.*/, 'security'])
```

**Combined Filters**
```ruby
# Complex multi-criteria filtering
OrderMessage.subscribe(
  from: /^(admin|system)-.*/, 
  to: ['order-service', /^fulfillment-.*/]
)

# Admin services to production only
AdminMessage.subscribe(from: /^admin-.*/, to: /^prod-.*/)
```

#### Filter Validation

Filters are validated at subscription time:

```ruby
# Valid filters
MyMessage.subscribe(from: 'service')           # String
MyMessage.subscribe(from: /^service-.*/)       # Regexp  
MyMessage.subscribe(from: ['a', /^b-.*/])      # Array of String/Regexp

# Invalid filters (raise ArgumentError)
MyMessage.subscribe(from: 123)                 # Invalid type
MyMessage.subscribe(from: ['valid', 123])      # Invalid array element
```

### Removing Subscriptions

```ruby
# Remove specific method handler
MyMessage.unsubscribe("MyMessage.custom_handler")

# Remove specific proc/block handler using returned ID
block_id = MyMessage.subscribe { |h,p| puts p }
MyMessage.unsubscribe(block_id)  # Cleans up proc from registry too

# Remove ALL handlers for a message class
MyMessage.unsubscribe!

# Remove all subscriptions (useful for testing)
dispatcher = SmartMessage::Dispatcher.new
dispatcher.drop_all!
```

### Viewing Subscriptions

```ruby
dispatcher = SmartMessage::Dispatcher.new

# View all subscriptions
puts dispatcher.subscribers
# => {"MyMessage" => ["MyMessage.process", "MyMessage.audit"]}

# Check specific message subscriptions
puts dispatcher.subscribers["MyMessage"]
# => ["MyMessage.process", "MyMessage.audit"]
```

## Message Routing Process

### 1. Message Reception

When a transport receives a message, it calls the dispatcher:

```ruby
# Transport receives serialized message and routes it
transport.receive(message_class, serialized_message)
# This internally decodes the message and calls:
dispatcher.route(decoded_message)
```

### 2. Subscription Lookup

The dispatcher finds all registered handlers:

```ruby
def route(decoded_message)
  message_klass = decoded_message._sm_header.message_class
  return nil if @subscribers[message_klass].empty?
  
  @subscribers[message_klass].each do |subscription|
    # Process each handler with filters
  end
end
```

### 3. Concurrent Processing

Each handler is processed in its own thread, with support for both method and proc handlers:

```ruby
@subscribers[message_klass].each do |subscription|
  message_processor = subscription[:process_method]
  SS.add(message_klass, message_processor, 'routed')
  
  @router_pool.post do
    # This runs in a separate thread with circuit breaker protection
    circuit_result = circuit(:message_processor).wrap do
      # Check if this is a proc handler or a regular method call
      if proc_handler?(message_processor)
        # Call the proc handler via SmartMessage::Base
        SmartMessage::Base.call_proc_handler(message_processor, decoded_message)
      else
        # Original method call logic
        parts = message_processor.split('.')
        target_klass = parts[0]  # "MyMessage" 
        class_method = parts[1]  # "process"
        
        target_klass.constantize
                    .method(class_method)
                    .call(decoded_message)
      end
    end
    
    # Handle circuit breaker fallback if triggered
    if circuit_result.is_a?(Hash) && circuit_result[:circuit_breaker]
      handle_circuit_breaker_fallback(circuit_result, decoded_message, message_processor)
    end
  end
end
```

**Handler Types Processed:**
- **Method handlers**: `"ClassName.method_name"` → resolved via constantize
- **Proc handlers**: `"ClassName.proc_abc123"` → looked up in proc registry  
- **Block handlers**: `"ClassName.proc_def456"` → treated as proc handlers
- **Lambda handlers**: `"ClassName.proc_ghi789"` → treated as proc handlers

## Thread Pool Management

### Thread Pool Configuration

The dispatcher uses `Concurrent::CachedThreadPool` which automatically manages thread creation and destruction:

```ruby
def initialize
  @router_pool = Concurrent::CachedThreadPool.new
  
  # Automatic cleanup on exit
  at_exit do
    shutdown_thread_pool
  end
end
```

### Monitoring Thread Pool Status

```ruby
dispatcher = SmartMessage::Dispatcher.new

# Get comprehensive status
status = dispatcher.status
puts "Running: #{status[:running]}"
puts "Queue length: #{status[:queue_length]}"
puts "Scheduled tasks: #{status[:scheduled_task_count]}"
puts "Completed tasks: #{status[:completed_task_count]}"
puts "Current threads: #{status[:length]}"

# Individual status methods
puts dispatcher.running?              # Is the pool active?
puts dispatcher.queue_length          # How many tasks are waiting?
puts dispatcher.scheduled_task_count  # Total tasks scheduled
puts dispatcher.completed_task_count  # Total tasks completed
puts dispatcher.current_length        # Current number of threads
```

### Thread Pool Lifecycle

```ruby
# Automatic shutdown handling
at_exit do
  print "Shutting down the dispatcher's thread pool..."
  @router_pool.shutdown
  
  while @router_pool.shuttingdown?
    print '.'
    sleep 1
  end
  
  puts " done."
end
```

## Message Processing Patterns

### Standard Processing

```ruby
class OrderMessage < SmartMessage::Base
  property :order_id
  property :customer_id
  property :items
  
  # Standard process method
  def self.process(message_header, message_payload)
    # 1. Decode the message
    data = JSON.parse(message_payload)
    order = new(data)
    
    # 2. Execute business logic
    fulfill_order(order)
    
    # 3. Optional: publish follow-up messages
    ShippingMessage.new(
      order_id: order.order_id,
      address: get_shipping_address(order.customer_id)
    ).publish
  end
  
  private
  
  def self.fulfill_order(order)
    # Business logic here
  end
end

# Subscribe to receive messages
OrderMessage.subscribe
```

### Multiple Handlers

```ruby
class PaymentMessage < SmartMessage::Base
  property :payment_id
  property :amount
  property :customer_id
  
  # Primary payment processing
  def self.process(message_header, message_payload)
    data = JSON.parse(message_payload)
    payment = new(data)
    
    process_payment(payment)
  end
  
  # Audit logging handler
  def self.audit(message_header, message_payload)
    data = JSON.parse(message_payload)
    payment = new(data)
    
    log_payment_attempt(payment)
  end
  
  # Fraud detection handler
  def self.fraud_check(message_header, message_payload)
    data = JSON.parse(message_payload)
    payment = new(data)
    
    if suspicious_payment?(payment)
      flag_for_review(payment)
    end
  end
end

# Register all handlers
PaymentMessage.subscribe("PaymentMessage.process")
PaymentMessage.subscribe("PaymentMessage.audit")
PaymentMessage.subscribe("PaymentMessage.fraud_check")
```

### Error Handling in Processors

```ruby
class RobustMessage < SmartMessage::Base
  property :data
  
  def self.process(message_header, message_payload)
    begin
      data = JSON.parse(message_payload)
      message = new(data)
      
      # Main processing logic
      process_business_logic(message)
      
    rescue JSON::ParserError => e
      # Handle malformed messages
      log_error("Invalid message format", message_header, e)
      
    rescue BusinessLogicError => e
      # Handle business logic failures
      log_error("Business logic failed", message_header, e)
      
      # Optionally republish to error queue
      ErrorMessage.new(
        original_message: message_payload,
        error: e.message,
        retry_count: get_retry_count(message_header)
      ).publish
      
    rescue => e
      # Handle unexpected errors
      log_error("Unexpected error", message_header, e)
      raise  # Re-raise to trigger dispatcher error handling
    end
  end
  
  private
  
  def self.log_error(type, header, error)
    puts "#{type}: #{error.message}"
    puts "Message class: #{header.message_class}"
    puts "Message UUID: #{header.uuid}"
  end
end
```

## Advanced Routing Patterns

### Conditional Processing

```ruby
class ConditionalMessage < SmartMessage::Base
  property :environment
  property :data
  
  def self.process(message_header, message_payload)
    data = JSON.parse(message_payload)
    message = new(data)
    
    # Route based on message content
    case message.environment
    when 'production'
      production_handler(message)
    when 'staging'
      staging_handler(message)
    when 'development'
      development_handler(message)
    else
      default_handler(message)
    end
  end
end
```

### Message Transformation and Republishing

```ruby
class TransformMessage < SmartMessage::Base
  property :raw_data
  property :format
  
  def self.process(message_header, message_payload)
    data = JSON.parse(message_payload)
    message = new(data)
    
    # Transform the message
    case message.format
    when 'csv'
      transformed = transform_csv(message.raw_data)
    when 'xml'
      transformed = transform_xml(message.raw_data)
    else
      transformed = message.raw_data
    end
    
    # Republish as a different message type
    ProcessedMessage.new(
      original_id: message_header.uuid,
      processed_data: transformed,
      processed_at: Time.now
    ).publish
  end
end
```

### Fan-out Processing

```ruby
class EventMessage < SmartMessage::Base
  property :event_type
  property :user_id
  property :data
  
  def self.process(message_header, message_payload)
    data = JSON.parse(message_payload)
    event = new(data)
    
    # Fan out to multiple specialized handlers
    case event.event_type
    when 'user_signup'
      WelcomeEmailMessage.new(user_id: event.user_id).publish
      AnalyticsMessage.new(event: 'signup', user_id: event.user_id).publish
      AuditMessage.new(action: 'user_created', user_id: event.user_id).publish
      
    when 'purchase'
      InventoryMessage.new(items: event.data['items']).publish
      ReceiptMessage.new(user_id: event.user_id, total: event.data['total']).publish
      LoyaltyMessage.new(user_id: event.user_id, points: calculate_points(event.data)).publish
    end
  end
end
```

## Statistics and Monitoring

### Built-in Statistics

The dispatcher automatically collects statistics via the `SimpleStats` (`SS`) system:

```ruby
# Statistics are automatically collected for:
# - Message publishing: SS.add(message_class, 'publish')
# - Message routing: SS.add(message_class, process_method, 'routed')

# View all statistics
puts SS.stat

# Get specific statistics
publish_count = SS.get("MyMessage", "publish")
process_count = SS.get("MyMessage", "MyMessage.process", "routed")

# Reset statistics
SS.reset  # Clear all
SS.reset("MyMessage", "publish")  # Clear specific stat
```

### Custom Monitoring

```ruby
class MonitoredMessage < SmartMessage::Base
  property :data
  
  def self.process(message_header, message_payload)
    start_time = Time.now
    
    begin
      # Process the message
      data = JSON.parse(message_payload)
      message = new(data)
      
      process_business_logic(message)
      
      # Record success metrics
      record_processing_time(Time.now - start_time)
      increment_success_counter
      
    rescue => e
      # Record failure metrics
      record_error(e)
      increment_failure_counter
      raise
    end
  end
  
  private
  
  def self.record_processing_time(duration)
    SS.add("MonitoredMessage", "processing_time", how_many: duration)
  end
  
  def self.increment_success_counter
    SS.add("MonitoredMessage", "success")
  end
  
  def self.increment_failure_counter
    SS.add("MonitoredMessage", "failure")
  end
end
```

## Performance Considerations

### Thread Pool Sizing

The `CachedThreadPool` automatically manages thread creation, but you can influence behavior:

```ruby
# For high-throughput scenarios, consider a custom thread pool
class CustomDispatcher < SmartMessage::Dispatcher
  def initialize(min_threads: 5, max_threads: 50)
    @router_pool = Concurrent::ThreadPoolExecutor.new(
      min_threads: min_threads,
      max_threads: max_threads,
      max_queue: 1000,
      fallback_policy: :caller_runs
    )
    
    # Rest of initialization
  end
end
```

### Processing Optimization

```ruby
class OptimizedMessage < SmartMessage::Base
  property :data
  
  def self.process(message_header, message_payload)
    # Parse once, use multiple times
    data = JSON.parse(message_payload)
    message = new(data)
    
    # Batch operations when possible
    batch_operations(message)
    
    # Use connection pooling for database operations
    connection_pool.with do |conn|
      save_to_database(message, conn)
    end
  end
end
```

## Testing Dispatcher Behavior

### Dispatcher Testing

```ruby
RSpec.describe SmartMessage::Dispatcher do
  let(:dispatcher) { SmartMessage::Dispatcher.new }
  
  before do
    dispatcher.drop_all!  # Clear subscriptions
  end
  
  describe "subscription management" do
    it "adds subscriptions" do
      dispatcher.add("TestMessage", "TestMessage.process")
      
      expect(dispatcher.subscribers["TestMessage"]).to include("TestMessage.process")
    end
    
    it "removes subscriptions" do
      dispatcher.add("TestMessage", "TestMessage.process")
      dispatcher.drop("TestMessage", "TestMessage.process")
      
      expect(dispatcher.subscribers["TestMessage"]).not_to include("TestMessage.process")
    end
  end
  
  describe "message routing" do
    let(:header) { double("header", message_class: "TestMessage") }
    let(:payload) { '{"data": "test"}' }
    
    before do
      # Mock the message class
      stub_const("TestMessage", Class.new do
        def self.process(header, payload)
          @processed_messages ||= []
          @processed_messages << [header, payload]
        end
        
        def self.processed_messages
          @processed_messages || []
        end
      end)
    end
    
    it "routes messages to subscribers" do
      dispatcher.add("TestMessage", "TestMessage.process")
      dispatcher.route(header, payload)
      
      # Wait for async processing
      sleep 0.1
      
      expect(TestMessage.processed_messages).to have(1).message
    end
  end
end
```

### Message Processing Testing

```ruby
RSpec.describe "Message Processing" do
  let(:transport) { SmartMessage::Transport.create(:memory, auto_process: true) }
  
  before do
    TestMessage.config do
      transport transport
      serializer SmartMessage::Serializer::JSON.new
    end
    
    TestMessage.subscribe
  end
  
  it "processes published messages" do
    expect(TestMessage).to receive(:process).once
    
    TestMessage.new(data: "test").publish
    
    # Wait for async processing
    sleep 0.1
  end
end
```

## Next Steps

- [Thread Safety](thread-safety.md) - Understanding concurrent processing
- [Statistics & Monitoring](monitoring.md) - Detailed monitoring guide
- [Custom Transports](custom-transports.md) - How transports interact with the dispatcher
- [Troubleshooting](troubleshooting.md) - Common dispatcher issues