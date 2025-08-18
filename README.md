# SmartMessage

[![Gem Version](https://badge.fury.io/rb/smart_message.svg)](https://badge.fury.io/rb/smart_message)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0.0-ruby.svg)](https://www.ruby-lang.org/en/)

SmartMessage is a message abstraction framework that decouples business logic from message transports and serialization formats. Much like ActiveRecord abstracts models from database implementations, SmartMessage abstracts messages from their backend transport and serialization mechanisms.

## Features

- **Transport Abstraction**: Plugin architecture supporting multiple message transports (RabbitMQ, Kafka, etc.)
- **Serialization Flexibility**: Pluggable serialization formats (JSON, MessagePack, etc.)
- **Dual-Level Configuration**: Class and instance-level plugin overrides for gateway patterns
- **Concurrent Processing**: Thread-safe message routing using `Concurrent::CachedThreadPool`
- **Built-in Statistics**: Message processing metrics and monitoring
- **Development Tools**: STDOUT and in-memory transports for testing

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'smart_message'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install smart_message

## Quick Start

### 1. Define a Message Class

```ruby
class OrderMessage < SmartMessage::Base
  property :order_id, description: "Unique order identifier"
  property :customer_id, description: "Customer's unique ID"
  property :amount, description: "Total order amount in dollars"
  property :items, description: "Array of ordered items"

  # Configure transport and serializer at class level
  config do
    transport SmartMessage::Transport.create(:stdout, loopback: true)
    serializer SmartMessage::Serializer::JSON.new
  end

  # Business logic for processing received messages
  def self.process(message_header, message_payload)
    # Decode the message
    order_data = JSON.parse(message_payload)
    order = new(order_data)
    
    # Process the order
    puts "Processing order #{order.order_id} for customer #{order.customer_id}"
    puts "Amount: $#{order.amount}"
    
    # Your business logic here
    process_order(order)
  end

  private

  def self.process_order(order)
    # Implementation specific to your domain
  end
end
```

### 2. Publish Messages

```ruby
# Create and publish a message
order = OrderMessage.new(
  order_id: "ORD-123",
  customer_id: "CUST-456", 
  amount: 99.99,
  items: ["Widget A", "Widget B"]
)

order.publish
```

### 3. Subscribe to Messages

```ruby
# Subscribe to process incoming OrderMessage instances
OrderMessage.subscribe

# Or specify a custom processing method
OrderMessage.subscribe("OrderMessage.custom_processor")
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

- **StdoutTransport**: Development and testing transport
- **MemoryTransport**: In-memory queuing for testing
- **RedisTransport**: Redis pub/sub transport for production messaging
- **Custom Transports**: Implement `SmartMessage::Transport::Base`

#### Serializer System
Pluggable message encoding/decoding:

- **JSON Serializer**: Built-in JSON support
- **Custom Serializers**: Implement `SmartMessage::Serializer::Base`

#### Dispatcher
Concurrent message routing engine that:
- Uses thread pools for async processing
- Routes messages to subscribed handlers
- Provides processing statistics
- Handles graceful shutdown

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

### STDOUT Transport (Development)

```ruby
# Basic STDOUT output
transport = SmartMessage::Transport.create(:stdout)

# With loopback for testing subscriptions
transport = SmartMessage::Transport.create(:stdout, loopback: true)

# Output to file
transport = SmartMessage::Transport.create(:stdout, output: "messages.log")
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
2. **Configuration**: Set transport, serializer, and logger plugins
3. **Publishing**: Message instance is encoded and sent through transport
4. **Subscription**: Message classes register with dispatcher for processing
5. **Processing**: Received messages are decoded and `process` method is called

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