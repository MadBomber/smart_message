<table border="0">
<tr>
<td width="30%" valign="top">

<img src="docs/assets/images/smart_message.jpg" alt="SmartMessage Logo" />
<br/>
See <a href="https://madbomber.github.io/smart_message/">Documentation Websit</a>
</td>
<td width="70%" valign="top">

# SmartMessage

Can Walk, Talk, and Think at the Same Time

**SmartMessage** is a powerful Ruby framework that transforms ordinary messages into intelligent, self-aware entities capable of routing themselves, validating their contents, and executing business logic. By abstracting away the complexities of transport mechanisms (Redis, RabbitMQ, Kafka) and serialization formats (JSON, MessagePack), SmartMessage lets you focus on what matters: your business logic.

Think of SmartMessage as ActiveRecord for messaging - just as ActiveRecord frees you from database-specific SQL, SmartMessage liberates your messages from transport-specific implementations. Each message knows how to validate itself, where it came from, where it's going, and what to do when it arrives. With built-in support for filtering, versioning, deduplication, and concurrent processing, SmartMessage provides enterprise-grade messaging capabilities with the simplicity Ruby developers love.

</td>
</tr>
</table>

## Features

- **Transport Abstraction**: Plugin architecture supporting multiple message transports (Redis, RabbitMQ, Kafka, etc.)
- **Multi-Transport Publishing**: Send messages to multiple transports simultaneously for redundancy, integration, and migration scenarios
- **🌟 Redis Queue Transport**: Advanced transport with RabbitMQ-style routing patterns, persistent FIFO queues, load balancing, and 10x faster performance than traditional message brokers. Built on Ruby's Async framework for fiber-based concurrency supporting thousands of concurrent subscriptions - [see full documentation](docs/transports/redis-queue.md)
- **Serialization Flexibility**: Pluggable serialization formats (JSON, MessagePack, etc.)
- **Entity-to-Entity Addressing**: Built-in FROM/TO/REPLY_TO addressing for point-to-point and broadcast messaging patterns
- **Advanced Message Filtering**: Filter subscriptions using exact strings, regular expressions, or mixed arrays for precise message routing
- **Schema Versioning**: Built-in version management with automatic compatibility validation
- **Comprehensive Validation**: Property validation with custom error messages and automatic validation before publishing
- **Message Documentation**: Built-in documentation support for message classes and properties with automatic defaults
- **Flexible Message Handlers**: Multiple subscription patterns - default methods, custom methods, blocks, procs, and lambdas
- **Dual-Level Configuration**: Class and instance-level plugin overrides for gateway patterns
- **Concurrent Processing**: Thread-safe message routing using `Concurrent::CachedThreadPool` with Async/Fiber-based Redis Queue Transport for massive scalability
- **Advanced Logging System**: Comprehensive logging with colorized console output, JSON structured logging, and file rolling
- **Built-in Statistics**: Message processing metrics and monitoring
- **Message Deduplication**: Handler-scoped deduplication queues (DDQ) with memory or Redis storage for preventing duplicate message processing
- **Development Tools**: STDOUT transport for publish-only scenarios and in-memory transport for testing with local processing
- **Production Ready**: Redis transport with automatic reconnection and error handling
- **Dead Letter Queue**: File-based DLQ with JSON Lines format for failed message capture and replay
- **Circuit Breaker Integration**: Production-grade reliability with BreakerMachines for automatic fallback and recovery

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'smart_message'
```

And then execute:

    bundle install

Or install it yourself as:

    gem install smart_message

### Redis Transport Setup

To use the built-in Redis transport, you'll need to have Redis server installed:

**macOS:**
```bash
brew install redis
brew services start redis  # To start Redis as a service
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install redis-server
```

**CentOS/RHEL/Fedora:**
```bash
sudo yum install redis
sudo systemctl start redis
```

## Quick Start

### 1. Define a Message Class

```ruby
require 'smart_message'

class OrderMessage < SmartMessage::Base
  # Declare schema version for compatibility tracking
  version 2

  # Add a description for the message class
  description "Represents customer order data for processing and fulfillment"

  # Configure entity addressing (Method 1: Direct methods)
  from 'order-service'
  to 'fulfillment-service'  # Point-to-point message
  reply_to 'order-service'  # Responses come back here

  # Alternative Method 2: Using header block
  # header do
  #   from 'order-service'
  #   to 'fulfillment-service'
  #   reply_to 'order-service'
  # end

  # Required properties with validation
  property :order_id,
    required: true,
    message: "Order ID is required",
    validate: ->(v) { v.is_a?(String) && v.length > 0 },
    validation_message: "Order ID must be a non-empty string",
    description: "Unique order identifier"

  property :customer_id,
    required: true,
    message: "Customer ID is required",
    description: "Customer's unique ID"

  property :amount,
    required: true,
    message: "Amount is required",
    validate: ->(v) { v.is_a?(Numeric) && v > 0 },
    validation_message: "Amount must be a positive number",
    description: "Total order amount in dollars"

  property :items,
    default: [],
    description: "Array of ordered items"

  # Configure transport and serializer at class level
  config do
    # Option 1: Memory transport for local development with message processing
    transport SmartMessage::Transport::MemoryTransport.new

    # Option 2: Redis Queue for production (10x faster than RabbitMQ!)
    # transport SmartMessage::Transport.create(:redis_queue,
    #   url: 'redis://localhost:6379',
    #   queue_prefix: 'myapp'
    # )

    serializer SmartMessage::Serializer::JSON.new
  end

  # Business logic for processing received messages
  def self.process(message_instance)
    # Message instance is already decoded and validated
    puts "Processing order #{message_instance.order_id} for customer #{message_instance.customer_id}"
    puts "Amount: $#{message_instance.amount}"

    # Your business logic here
    process_order(message_instance)
  end

  private

  def self.process_order(order)
    # Implementation specific to your domain
  end
end
```

### 2. Publish Messages

```ruby
# Create and publish a message (automatically validated before publishing)
order = OrderMessage.new(
  order_id: "ORD-123",
  customer_id: "CUST-456",
  amount: 99.99,
  items: ["Widget A", "Widget B"]
)

# Message is automatically validated before publishing
order.publish  # Validates all properties, header, and version compatibility

# Or validate manually
if order.valid?
  order.publish
else
  errors = order.validation_errors
  errors.each { |err| puts "#{err[:property]}: #{err[:message]}" }
end
```

### 3. Subscribe to Messages

SmartMessage supports multiple ways to handle incoming messages:

```ruby
# 1. Default handler (uses self.process method)
OrderMessage.subscribe

# 2. Custom method handler
OrderMessage.subscribe("PaymentService.process_order")

# 3. Block handler (NEW!)
OrderMessage.subscribe do |message|
  puts "Quick processing: Order #{message.order_id}"
end

# 4. Proc handler (NEW!)
order_processor = proc do |message|
  EmailService.send_confirmation(message.customer_id)
end
OrderMessage.subscribe(order_processor)

# 5. Lambda handler (NEW!)
audit_handler = lambda do |message|
  AuditLog.record("Order processed at #{message._sm_header.published_at}")
end
OrderMessage.subscribe(audit_handler)
```

### 4. Message Filtering (NEW!)

SmartMessage supports powerful message filtering using exact strings, regular expressions, or arrays:

```ruby
# Filter by exact sender
OrderMessage.subscribe(from: 'payment-service')

# Filter by sender pattern (all payment services)
OrderMessage.subscribe(from: /^payment-.*/)

# Filter by multiple senders
OrderMessage.subscribe(from: ['admin', 'system', 'monitoring'])

# Mixed exact and pattern matching
OrderMessage.subscribe(from: ['admin', /^system-.*/, 'legacy-service'])

# Filter by recipient patterns
OrderMessage.subscribe(to: /^(dev|staging)-.*/)

# Combined filtering
OrderMessage.subscribe(
  from: /^admin-.*/,
  to: ['order-service', /^fulfillment-.*/]
)

# Environment-based routing
DevService.subscribe(to: /^(dev|staging)-.*/)
ProdService.subscribe(to: /^prod-.*/)
```

### 5. Message Deduplication

SmartMessage provides handler-scoped message deduplication to prevent duplicate processing of messages with the same UUID. Each handler gets its own Deduplication Queue (DDQ) that tracks recently processed message UUIDs.

#### Basic Deduplication Setup

```ruby
class OrderMessage < SmartMessage::Base
  version 1
  property :order_id, required: true
  property :amount, required: true

  from "order-service"

  # Configure deduplication
  ddq_size 100              # Track last 100 message UUIDs
  ddq_storage :memory       # Use memory storage (or :redis for distributed)
  enable_deduplication!     # Enable deduplication for this message class

  def self.process(message_instance)
    puts "Processing order: #{message_instance.order_id}"
    # Business logic here
  end
end
```

#### Handler-Scoped Isolation

Each handler gets its own DDQ scope, preventing cross-contamination between different subscribers:

```ruby
# Each handler gets separate deduplication tracking
OrderMessage.subscribe('PaymentService.process')     # DDQ: "OrderMessage:PaymentService.process"
OrderMessage.subscribe('FulfillmentService.handle')  # DDQ: "OrderMessage:FulfillmentService.handle"
OrderMessage.subscribe('AuditService.log_order')     # DDQ: "OrderMessage:AuditService.log_order"

# Same handler across message classes = separate DDQs
PaymentMessage.subscribe('PaymentService.process')   # DDQ: "PaymentMessage:PaymentService.process"
InvoiceMessage.subscribe('PaymentService.process')   # DDQ: "InvoiceMessage:PaymentService.process"
```

#### Storage Options

```ruby
# Memory-based DDQ (single process)
class LocalMessage < SmartMessage::Base
  ddq_size 50
  ddq_storage :memory
  enable_deduplication!
end

# Redis-based DDQ (distributed/multi-process)
class DistributedMessage < SmartMessage::Base
  ddq_size 1000
  ddq_storage :redis, redis_url: 'redis://localhost:6379', redis_db: 1
  enable_deduplication!
end
```

#### DDQ Statistics and Management

```ruby
# Check deduplication configuration
config = OrderMessage.ddq_config
puts "Enabled: #{config[:enabled]}"
puts "Size: #{config[:size]}"
puts "Storage: #{config[:storage]}"

# Get DDQ statistics
stats = OrderMessage.ddq_stats
puts "Current count: #{stats[:current_count]}"
puts "Utilization: #{stats[:utilization]}%"

# Clear DDQ if needed
OrderMessage.clear_ddq!

# Check if specific UUID is duplicate
OrderMessage.duplicate_uuid?("some-uuid-123")
```

#### How Deduplication Works

1. **Message Receipt**: When a message arrives, the dispatcher checks the handler's DDQ for the message UUID
2. **Duplicate Detection**: If UUID exists in DDQ, the message is ignored (logged but not processed)
3. **Processing**: If UUID is new, the message is processed by the handler
4. **UUID Storage**: After successful processing, the UUID is added to the handler's DDQ
5. **Circular Buffer**: When DDQ reaches capacity, oldest UUIDs are evicted to make room for new ones

#### Benefits

- **Handler Isolation**: Each handler maintains independent deduplication state
- **Cross-Process Support**: Redis DDQ enables deduplication across multiple processes
- **Memory Efficient**: Circular buffer with configurable size limits memory usage
- **High Performance**: O(1) UUID lookup using hybrid array + set data structure
- **Automatic Integration**: Seamlessly works with existing subscription patterns

### 6. Entity Addressing

SmartMessage supports entity-to-entity addressing with FROM/TO/REPLY_TO fields for advanced message routing. You can configure addressing using three different approaches:

#### Method 1: Direct Class Methods
```ruby
class PaymentMessage < SmartMessage::Base
  version 1
  from 'payment-service'     # Required: sender identity
  to 'bank-gateway'          # Optional: specific recipient
  reply_to 'payment-service' # Optional: where responses go

  property :amount, required: true
  property :account_id, required: true
end
```

#### Method 2: Header Block DSL
```ruby
class PaymentMessage < SmartMessage::Base
  version 1

  # Configure all addressing in a single block
  header do
    from 'payment-service'
    to 'bank-gateway'
    reply_to 'payment-service'
  end

  property :amount, required: true
  property :account_id, required: true
end
```

#### Method 3: Instance-Level Configuration
```ruby

# Create payment instance
payment = PaymentMessage.new(amount: 100.00, account_id: "ACCT-123")

# Override addressing at instance level
payment.to('backup-gateway')  # Method chaining supported
payment.from('urgent-processor')

# Alternative setter syntax
payment.from = 'urgent-processor'
payment.to = 'backup-gateway'

# Access addressing (shortcut methods)
puts payment.from      # => 'urgent-processor'
puts payment.to        # => 'backup-gateway'
puts payment.reply_to  # => 'payment-service'

# Access via header (full path)
puts payment._sm_header.from      # => 'urgent-processor'
puts payment._sm_header.to        # => 'backup-gateway'
puts payment._sm_header.reply_to  # => 'payment-service'

# Publish with updated addressing
payment.publish
```

#### Broadcast Messaging Example
```ruby
class SystemAnnouncementMessage < SmartMessage::Base
  version 1

  # Using header block for broadcast configuration
  header do
    from 'admin-service'  # Required: sender identity
    # No 'to' field = broadcast to all subscribers
  end

  property :message, required: true
  property :priority, default: 'normal'
end
```

#### Messaging Patterns Supported

- **Point-to-Point**: Set `to` field for direct entity targeting
- **Broadcast**: Omit `to` field (nil) for message broadcast to all subscribers
- **Request-Reply**: Use `reply_to` field to specify response routing
- **Gateway Patterns**: Override addressing at instance level for message forwarding

## Logging Configuration

SmartMessage includes a comprehensive logging system with support for multiple output formats, colorization, and file rolling capabilities.

### Basic Logging Configuration

```ruby
# Configure SmartMessage logging
SmartMessage.configure do |config|
  config.logger = STDOUT              # Output destination (file path, STDOUT, STDERR)
  config.log_level = :info           # Log level (:debug, :info, :warn, :error, :fatal)
  config.log_format = :text          # Output format (:text, :json)
  config.log_colorize = true         # Enable colorized console output
  config.log_include_source = false  # Include source file/line information
  config.log_structured_data = false # Enable structured data logging
end

# Access the configured logger in your application
logger = SmartMessage.configuration.default_logger
logger.info("Application started", component: "main", pid: Process.pid)
```

### Advanced Logging Features

#### Colorized Console Output
```ruby
SmartMessage.configure do |config|
  config.logger = STDOUT
  config.log_colorize = true
  config.log_format = :text
end

logger = SmartMessage.configuration.default_logger
logger.debug("Debug message")    # Green background, white text
logger.info("Info message")      # White text
logger.warn("Warning message")   # Yellow background, white bold text
logger.error("Error message")    # Light red background, white bold text
logger.fatal("Fatal message")    # Light red background, yellow bold text
```

#### JSON Structured Logging
```ruby
SmartMessage.configure do |config|
  config.logger = "log/application.log"
  config.log_format = :json
  config.log_structured_data = true
  config.log_include_source = true
end

logger = SmartMessage.configuration.default_logger
logger.info("User action",
            user_id: 12345,
            action: "login",
            ip_address: "192.168.1.1")
# Output: {"timestamp":"2025-01-15T10:30:45.123Z","level":"INFO","message":"User action","user_id":12345,"action":"login","ip_address":"192.168.1.1","source":"app.rb:42:in `authenticate`"}
```

#### File Rolling Configuration
```ruby
SmartMessage.configure do |config|
  config.logger = "log/application.log"
  config.log_options = {
    # Size-based rolling
    roll_by_size: true,
    max_file_size: 10 * 1024 * 1024,  # 10 MB
    keep_files: 5,                     # Keep 5 old files

    # Date-based rolling (alternative to size-based)
    roll_by_date: false,               # Set to true for date-based
    date_pattern: '%Y-%m-%d'           # Daily rolling pattern
  }
end
```

### SmartMessage Integration

SmartMessage classes automatically use the configured logger:

```ruby
class OrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :amount, required: true

  def process
    # Logger is automatically available
    logger.info("Processing order",
                order_id: order_id,
                amount: amount,
                header: _sm_header.to_h,
                payload: _sm_payload)
  end
end

# Messages inherit the global logger configuration
message = OrderMessage.new(order_id: "123", amount: 99.99)
message.publish  # Uses configured logger for any internal logging
```

## Architecture

### Core Components

#### SmartMessage::Base
The foundation class that all messages inherit from. Built on `Hashie::Dash` with extensions for:
- Property management and coercion
- Multi-level plugin configuration
- Message lifecycle management
- Automatic header generation (UUID, timestamps, process tracking)

#### Transport Layer
Pluggable message delivery system with built-in implementations:

- **StdoutTransport**: Publish-only transport for debugging and external integration
- **MemoryTransport**: In-memory queuing for testing with local message processing
- **RedisTransport**: Redis pub/sub transport for production messaging
- **Custom Transports**: Implement `SmartMessage::Transport::Base`

#### Serializer System
Pluggable message encoding/decoding:

- **JSON Serializer**: Built-in JSON support
- **Custom Serializers**: Implement `SmartMessage::Serializer::Base`

#### Dispatcher
Concurrent message routing engine that:
- Uses thread pools for async processing
- Routes messages to subscribed handlers with handler-scoped deduplication
- Provides processing statistics and DDQ management
- Handles graceful shutdown
- Maintains separate DDQ instances per handler for isolated deduplication tracking

### Plugin Architecture

SmartMessage supports two levels of plugin configuration:

```ruby
# Class-level configuration (default for all instances)
class MyMessage < SmartMessage::Base
  config do
    transport MyTransport.new
    serializer MySerializer.new
    logger MyLogger.new
  end
end

# Instance-level configuration (overrides class defaults)
message = MyMessage.new
message.config do
  transport DifferentTransport.new  # Override for this instance
end
```

This enables gateway patterns where messages can be received from one transport/serializer and republished to another.

## Transport Implementations

### Multi-Transport Messages

SmartMessage supports publishing to multiple transports simultaneously for redundancy, integration, and migration scenarios:

```ruby
class CriticalOrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :amount, required: true
  
  # Configure multiple transports - message goes to ALL of them
  transport [
    SmartMessage::Transport.create(:redis_queue, url: 'redis://primary:6379'),
    SmartMessage::Transport.create(:redis, url: 'redis://backup:6379'),
    SmartMessage::Transport::StdoutTransport.new(format: :json)
  ]
end

# Publishes to Redis Queue, Redis Pub/Sub, and STDOUT simultaneously
message = CriticalOrderMessage.new(order_id: "ORD-123", amount: 99.99)
message.publish  # ✅ Succeeds if ANY transport works

# Check transport configuration
puts message.multiple_transports?  # => true
puts message.transports.length     # => 3
```

**Key Benefits:**
- **Redundancy**: Messages reach multiple destinations for reliability
- **Integration**: Simultaneously log to STDOUT, send to Redis, and webhook external systems  
- **Migration**: Gradually transition between transport systems
- **Resilient**: Publishing succeeds as long as ANY transport works

### Redis Queue Transport (Featured) 🌟

The Redis Queue Transport provides enterprise-grade message routing with exceptional performance:

```ruby
# Configure with RabbitMQ-style routing
transport = SmartMessage::Transport.create(:redis_queue,
  url: 'redis://localhost:6379',
  queue_prefix: 'myapp',
  consumer_group: 'workers'
)

# Pattern-based subscriptions (RabbitMQ compatible)
transport.subscribe_pattern("#.*.payment_service")  # All messages TO payment_service
transport.subscribe_pattern("#.api_gateway.*")      # All messages FROM api_gateway
transport.subscribe_pattern("order.#.*.*")          # All order messages

# Fluent API for complex routing
transport.where
  .from('web_app')
  .to('analytics')
  .consumer_group('analytics_workers')
  .subscribe

# Configure message class
class OrderMessage < SmartMessage::Base
  transport :redis_queue

  property :order_id, required: true
  property :amount, required: true
end

# Publish with enhanced routing
OrderMessage.new(
  order_id: 'ORD-001',
  amount: 99.99,
  _sm_header: { from: 'api_gateway', to: 'payment_service' }
).publish
```

**Key Features:**
- 10x faster than RabbitMQ (0.5ms vs 5ms latency)
- Pattern routing with `#` and `*` wildcards
- Persistent FIFO queues using Redis Lists
- Load balancing via consumer groups
- Enhanced routing keys: `namespace.type.from.to`
- Queue monitoring and management
- Production-ready with circuit breakers and dead letter queues

📚 **Full Documentation:** [Redis Queue Transport Guide](docs/transports/redis-queue.md) | [Getting Started](docs/guides/redis-queue-getting-started.md) | [Examples](examples/redis_queue/)

### STDOUT Transport (Publish-Only)

The STDOUT transport is designed for publish-only scenarios - perfect for debugging, logging, or integration with external systems. Built as a minimal subclass of FileTransport, it inherits comprehensive formatting capabilities.

```ruby
# Basic STDOUT output (publish-only)
transport = SmartMessage::Transport::StdoutTransport.new

# JSON Lines format - one message per line (default)
transport = SmartMessage::Transport::StdoutTransport.new(format: :jsonl)

# Pretty-printed format with amazing_print for human reading
transport = SmartMessage::Transport::StdoutTransport.new(format: :pretty)

# Compact JSON format without newlines
transport = SmartMessage::Transport::StdoutTransport.new(format: :json)

# Output to file instead of STDOUT
transport = SmartMessage::Transport::StdoutTransport.new(file_path: "messages.log")
```

**Key Features:**
- **Publish-only**: No message processing or loopback
- **Subscription attempts are ignored** with warning logs
- **Three formats**: `:jsonl` (default), `:pretty` for debugging, `:json` for compact output
- **Flexible Output**: Defaults to STDOUT but can write to files when `file_path` specified
- **Perfect for**: debugging, logging, piping to external tools
- **Use cases**: `./app | jq '.first_name'`, `./app | fluentd`, development monitoring

**For local message processing, use MemoryTransport instead:**
```ruby
# Use Memory transport if you need local message processing
transport = SmartMessage::Transport::MemoryTransport.new
```

### Memory Transport (Testing)

```ruby
# Auto-process messages as they're published
transport = SmartMessage::Transport.create(:memory, auto_process: true)

# Store messages without processing
transport = SmartMessage::Transport.create(:memory, auto_process: false)

# Check stored messages
puts transport.message_count
puts transport.all_messages
transport.process_all  # Process all pending messages
```

### Redis Transport (Production)

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

# Configure message class to use Redis
MyMessage.config do
  transport SmartMessage::Transport.create(:redis, url: 'redis://localhost:6379')
  serializer SmartMessage::Serializer::JSON.new
end

# Subscribe to messages (uses message class name as Redis channel)
MyMessage.subscribe

# Publish messages (automatically publishes to Redis channel named "MyMessage")
message = MyMessage.new(data: "Hello Redis!")
message.publish
```

The Redis transport uses the message class name as the Redis channel name, enabling automatic routing of messages to their appropriate handlers.

### Custom Transport

```ruby
class WebhookTransport < SmartMessage::Transport::Base
  def default_options
    {
      webhook_url: "https://api.example.com/webhooks",
      timeout: 30,
      retries: 3
    }
  end

  def configure
    require 'net/http'
    @uri = URI(@options[:webhook_url])
  end

  def publish(message_header, message_payload)
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = @uri.scheme == 'https'

    request = Net::HTTP::Post.new(@uri)
    request['Content-Type'] = 'application/json'
    request['X-Message-Class'] = message_header.message_class
    request.body = message_payload

    response = http.request(request)
    raise "Webhook failed: #{response.code}" unless response.code.to_i < 400
  end

  def subscribe(message_class, process_method)
    super
    # For webhooks, subscription would typically be configured
    # externally on the webhook provider's side
  end
end

# Register the transport
SmartMessage::Transport.register(:webhook, WebhookTransport)

# Use the transport
MyMessage.config do
  transport SmartMessage::Transport.create(:webhook,
    webhook_url: "https://api.myservice.com/messages"
  )
end
```

## Message Lifecycle

1. **Definition**: Create message class inheriting from `SmartMessage::Base`
2. **Configuration**: Set transport, serializer, logger plugins, and entity addressing (from/to/reply_to)
3. **Validation**: Messages are automatically validated before publishing (properties, header, addressing, version compatibility)
4. **Publishing**: Message instance is encoded with addressing metadata and sent through transport
5. **Subscription**: Message classes register handlers with dispatcher for processing
   - Default handlers (`self.process` method)
   - Custom method handlers (`"ClassName.method_name"`)
   - Block handlers (`subscribe do |h,p|...end`)
   - Proc/Lambda handlers (`subscribe(proc {...})`)
6. **Routing**: Dispatcher uses addressing metadata to route messages (point-to-point vs broadcast)
7. **Processing**: Received messages are decoded and routed to registered handlers

## Schema Versioning and Validation

SmartMessage includes comprehensive validation and versioning capabilities to ensure message integrity and schema evolution support.

### Version Declaration

Declare your message schema version using the `version` class method:

```ruby
class OrderMessage < SmartMessage::Base
  version 2  # Schema version 2

  property :order_id, required: true
  property :customer_email  # Added in version 2
end
```

### Property Validation

Properties support multiple validation types with custom error messages:

```ruby
class UserMessage < SmartMessage::Base
  version 1

  # Required field validation (Hashie built-in)
  property :user_id,
    required: true,
    message: "User ID is required and cannot be blank"

  # Custom validation with lambda
  property :age,
    validate: ->(v) { v.is_a?(Integer) && v.between?(1, 120) },
    validation_message: "Age must be an integer between 1 and 120"

  # Email validation with regex
  property :email,
    validate: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
    validation_message: "Must be a valid email address"

  # Inclusion validation with array
  property :status,
    validate: ['active', 'inactive', 'pending'],
    validation_message: "Status must be active, inactive, or pending"
end
```

### Validation Methods

All message instances include validation methods:

```ruby
user = UserMessage.new(user_id: "123", age: 25)

# Validate entire message (properties + header + version)
user.validate!           # Raises SmartMessage::Errors::ValidationError on failure
user.valid?              # Returns true/false

# Get detailed validation errors
errors = user.validation_errors
errors.each do |error|
  puts "#{error[:source]}.#{error[:property]}: #{error[:message]}"
  # Example output:
  # message.age: Age must be an integer between 1 and 120
  # header.version: Header version must be a positive integer
  # version_mismatch.version: Expected version 1, got: 2
end
```

### Automatic Validation

Messages are automatically validated during publishing:

```ruby
# This will raise ValidationError if invalid
message = UserMessage.new(user_id: "", age: 150)
message.publish  # Automatically validates before publishing
```

### Version Compatibility

The framework automatically validates version compatibility:

```ruby
class V2Message < SmartMessage::Base
  version 2
  property :data
end

message = V2Message.new(data: "test")
# Header automatically gets version: 2

# Simulate version mismatch (e.g., from older message)
message._sm_header.version = 1
message.validate!  # Raises: "V2Message expects version 2, but header has version 1"
```

### Supported Validation Types

- **Proc/Lambda**: `validate: ->(v) { v.length > 5 }`
- **Regexp**: `validate: /\A[a-z]+\z/`
- **Class**: `validate: String` (type checking)
- **Array**: `validate: ['red', 'green', 'blue']` (inclusion)
- **Range**: `validate: (1..100)` (range checking)
- **Symbol**: `validate: :custom_validator_method`

## Message Documentation

SmartMessage provides built-in documentation capabilities for both message classes and their properties.

### Class-Level Descriptions

Use the `description` DSL method to document what your message class represents:

```ruby
class OrderMessage < SmartMessage::Base
  description "Represents customer order data for processing and fulfillment"

  property :order_id, required: true
  property :amount, required: true
end

class UserMessage < SmartMessage::Base
  description "Handles user management operations including registration and updates"

  property :user_id, required: true
  property :email, required: true
end

# Access descriptions
puts OrderMessage.description
# => "Represents customer order data for processing and fulfillment"

puts UserMessage.description
# => "Handles user management operations including registration and updates"

# Instance access to class description
order = OrderMessage.new(order_id: "123", amount: 99.99)
puts order.description
# => "Represents customer order data for processing and fulfillment"
```

### Default Descriptions

Classes without explicit descriptions automatically get a default description:

```ruby
class MyMessage < SmartMessage::Base
  property :data
end

puts MyMessage.description
# => "MyMessage is a SmartMessage"
```

### Property Documentation

Combine class descriptions with property descriptions for comprehensive documentation:

```ruby
class FullyDocumented < SmartMessage::Base
  description "A fully documented message class for demonstration purposes"

  property :id,
    description: "Unique identifier for the record"
  property :name,
    description: "Display name for the entity"
  property :status,
    description: "Current processing status",
    validate: ['active', 'inactive', 'pending']
end

# Access all documentation
puts FullyDocumented.description
# => "A fully documented message class for demonstration purposes"

puts FullyDocumented.property_description(:id)
# => "Unique identifier for the record"

puts FullyDocumented.property_descriptions
# => {:id=>"Unique identifier for the record", :name=>"Display name for the entity", ...}
```

### Documentation in Config Blocks

You can also set descriptions within configuration blocks:

```ruby
class ConfiguredMessage < SmartMessage::Base
  config do
    description "Set within config block"
    transport SmartMessage::Transport::MemoryTransport.new
    serializer SmartMessage::Serializer::Json.new
  end
end
```

## Advanced Usage

### Statistics and Monitoring

SmartMessage includes built-in statistics collection:

```ruby
# Access global statistics
puts SS.stat  # Shows all collected statistics

# Get specific counts
publish_count = SS.get("MyMessage", "publish")
process_count = SS.get("MyMessage", "MyMessage.process", "routed")

# Reset statistics
SS.reset  # Clear all stats
SS.reset("MyMessage", "publish")  # Reset specific stat
```

### Dispatcher Status

```ruby
dispatcher = SmartMessage::Dispatcher.new

# Check thread pool status
status = dispatcher.status
puts "Running: #{status[:running]}"
puts "Queue length: #{status[:queue_length]}"
puts "Completed tasks: #{status[:completed_task_count]}"

# Check subscriptions
puts dispatcher.subscribers
```

### Message Properties and Headers

```ruby
class MyMessage < SmartMessage::Base
  property :user_id, description: "User's unique identifier"
  property :action, description: "Action performed by the user"
  property :timestamp, default: -> { Time.now }, description: "When the action occurred"
end

message = MyMessage.new(user_id: 123, action: "login")

# Access message properties
puts message.user_id
puts message.fields  # Returns Set of property names (excluding internal _sm_ properties)

# Access property descriptions
puts MyMessage.property_description(:user_id)  # => "User's unique identifier"
puts MyMessage.property_descriptions            # => Hash of all descriptions

# Access message header
puts message._sm_header.uuid
puts message._sm_header.message_class
puts message._sm_header.published_at
puts message._sm_header.publisher_pid
puts message._sm_header.from
puts message._sm_header.to
puts message._sm_header.reply_to
```

### Dead Letter Queue

SmartMessage includes a comprehensive file-based Dead Letter Queue system for handling failed messages:

```ruby
# Configure global DLQ (optional - defaults to 'dead_letters.jsonl')
SmartMessage::DeadLetterQueue.configure_default('/var/log/app/dlq.jsonl')

# Or use environment-based configuration
SmartMessage::DeadLetterQueue.configure_default(
  ENV.fetch('SMART_MESSAGE_DLQ_PATH', 'dead_letters.jsonl')
)

# Access the default DLQ instance
dlq = SmartMessage::DeadLetterQueue.default

# Create a custom DLQ instance for specific needs
custom_dlq = SmartMessage::DeadLetterQueue.new('/tmp/critical_failures.jsonl')
```

#### DLQ Operations

```ruby
# Messages are automatically captured when circuit breakers trip
# But you can also manually enqueue failed messages:
dlq.enqueue(
  message._sm_header,
  message_payload,
  error: "Connection timeout",
  transport: "Redis",
  retry_count: 3
)

# Inspect queue status
puts "Queue size: #{dlq.size}"
puts "Next message: #{dlq.peek}"  # Look without removing

# Get statistics
stats = dlq.statistics
puts "Total messages: #{stats[:total]}"
puts "By error type: #{stats[:by_error]}"
puts "By message class: #{stats[:by_class]}"
```

#### Message Replay

```ruby
# Replay messages back through their original transport
dlq.replay_one           # Replay oldest message
dlq.replay_batch(10)      # Replay next 10 messages
dlq.replay_all            # Replay entire queue

# Replay with a different transport
redis_transport = SmartMessage::Transport.create(:redis)
dlq.replay_one(redis_transport)  # Override original transport
```

#### Administrative Functions

```ruby
# Filter messages for analysis
failed_orders = dlq.filter_by_class('OrderMessage')
timeout_errors = dlq.filter_by_error_pattern(/timeout/i)

# Export messages within a time range
yesterday = Time.now - 86400
today = Time.now
recent_failures = dlq.export_range(yesterday, today)

# Clear the queue when needed
dlq.clear  # Remove all messages
```

#### Integration with Circuit Breakers

Dead Letter Queue is automatically integrated with circuit breakers:

```ruby
class PaymentMessage < SmartMessage::Base
  config do
    transport SmartMessage::Transport.create(:redis)
    # Messages automatically go to DLQ when circuit breaker trips
  end
end

# Monitor circuit breaker status
transport = PaymentMessage.transport
stats = transport.transport_circuit_stats
if stats[:transport_publish][:open]
  puts "Circuit open - messages going to DLQ"
end
```

## Development

After checking out the repo, run:

```bash
bin/setup      # Install dependencies
bin/console    # Start interactive console
rake test      # Run test suite
```

### Testing

SmartMessage uses Minitest with Shoulda for testing:

```bash
rake test                           # Run all tests
ruby -Ilib:test test/base_test.rb  # Run specific test file
```

Test output and debug information is logged to `test.log`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MadBomber/smart_message.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
