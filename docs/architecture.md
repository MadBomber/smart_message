# SmartMessage Architecture

SmartMessage follows a plugin-based architecture that cleanly separates message concerns from transport and serialization mechanisms.

## Design Philosophy

SmartMessage is designed around the principle that **messages should be independent of their delivery mechanism**. Just as ActiveRecord abstracts database operations from business logic, SmartMessage abstracts message delivery from message content.

### Core Principles

1. **Separation of Concerns**: Message content, transport, and serialization are independent
2. **Plugin Architecture**: Pluggable transports and serializers
3. **Dual Configuration**: Both class-level and instance-level configuration
4. **Thread Safety**: Concurrent message processing with thread pools
5. **Gateway Support**: Messages can flow between different transports/serializers

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    SmartMessage::Base                       │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐│
│  │    Message      │ │   Transport     │ │   Serializer    ││
│  │   Properties    │ │     Plugin      │ │     Plugin      ││
│  │                 │ │                 │ │                 ││
│  │ • user_id       │ │ • publish()     │ │ • encode()      ││
│  │ • action        │ │ • subscribe()   │ │ • decode()      ││
│  │ • timestamp     │ │ • receive()     │ │                 ││
│  └─────────────────┘ └─────────────────┘ └─────────────────┘│
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
                    ┌─────────────────────┐
                    │     Dispatcher      │
                    │                     │
                    │ • Route messages    │
                    │ • Thread pool       │
                    │ • Subscriptions     │
                    └─────────────────────┘
                                │
                                ▼
                    ┌─────────────────────┐
                    │  Business Logic     │
                    │                     │
                    │ • process() method  │
                    │ • Domain logic      │
                    └─────────────────────┘
```

## Core Components

### 1. SmartMessage::Base

The foundation class that all messages inherit from, built on `Hashie::Dash`.

**Key Responsibilities:**
- Property management and validation
- Plugin configuration (transport, serializer, logger)
- Message lifecycle management
- Header generation and management

**Location:** `lib/smart_message/base.rb:11-278`

```ruby
class MyMessage < SmartMessage::Base
  property :data
  
  config do
    transport MyTransport.new
    serializer MySerializer.new
  end
end
```

### 2. Transport Layer

Handles message delivery and routing between systems.

**Key Responsibilities:**
- Message publishing and receiving
- Subscription management
- Connection handling
- Transport-specific configuration

**Location:** `lib/smart_message/transport/`

```ruby
# Transport interface
class CustomTransport < SmartMessage::Transport::Base
  def publish(message_header, message_payload)
    # Send message via your transport
  end
  
  def subscribe(message_class, process_method)
    # Set up subscription
  end
end
```

### 3. Serializer System

Handles encoding and decoding of message content.

**Key Responsibilities:**
- Message encoding (Ruby object → wire format)
- Message decoding (wire format → Ruby object)
- Format-specific handling

**Location:** `lib/smart_message/serializer/`

```ruby
class CustomSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    # Convert to wire format
  end
  
  def decode(payload)
    # Convert from wire format
  end
end
```

### 4. Dispatcher

Routes incoming messages to appropriate handlers using concurrent processing.

**Key Responsibilities:**
- Message routing based on class
- Thread pool management
- Subscription catalog management
- Statistics collection

**Location:** `lib/smart_message/dispatcher.rb:11-147`

```ruby
dispatcher = SmartMessage::Dispatcher.new
dispatcher.add("MyMessage", "MyMessage.process")
dispatcher.route(header, payload)
```

### 5. Message Headers

Standard metadata attached to every message.

**Key Responsibilities:**
- Message identification (UUID)
- Routing information (message class)
- Tracking data (timestamps, process IDs)

**Location:** `lib/smart_message/header.rb:9-20`

```ruby
header = message._sm_header
puts header.uuid          # "550e8400-e29b-41d4-a716-446655440000"
puts header.message_class # "MyMessage"
puts header.published_at  # 2025-08-17 10:30:00 UTC
```

## Message Lifecycle

### 1. Definition Phase
```ruby
class OrderMessage < SmartMessage::Base
  property :order_id
  property :amount
  
  config do
    transport SmartMessage::Transport.create(:memory)
    serializer SmartMessage::Serializer::JSON.new
  end
end
```

### 2. Subscription Phase
```ruby
OrderMessage.subscribe
# Registers "OrderMessage.process" with dispatcher
```

### 3. Publishing Phase
```ruby
order = OrderMessage.new(order_id: "123", amount: 99.99)
order.publish
# 1. Creates header with UUID, timestamp, etc.
# 2. Encodes message via serializer
# 3. Sends via transport
```

### 4. Receiving Phase
```ruby
# Transport receives message
transport.receive(header, payload)
# 1. Routes to dispatcher
# 2. Dispatcher finds subscribers
# 3. Spawns thread for processing
# 4. Calls OrderMessage.process(header, payload)
```

### 5. Processing Phase
```ruby
def self.process(message_header, message_payload)
  # 1. Decode payload
  data = JSON.parse(message_payload)
  order = new(data)
  
  # 2. Execute business logic
  fulfill_order(order)
end
```

## Plugin System Architecture

### Dual-Level Configuration

SmartMessage supports configuration at both class and instance levels:

```ruby
# Class-level (default for all instances)
class PaymentMessage < SmartMessage::Base
  config do
    transport ProductionTransport.new
    serializer SecureSerializer.new
  end
end

# Instance-level (overrides class configuration)
test_payment = PaymentMessage.new(amount: 1.00)
test_payment.config do
  transport TestTransport.new  # Override for this instance
end
```

This enables sophisticated gateway patterns where messages can be:
- Received from one transport (e.g., RabbitMQ)
- Processed with business logic
- Republished to another transport (e.g., Kafka)

### Plugin Registration

Transports are registered in a central registry:

```ruby
# Register custom transport
SmartMessage::Transport.register(:redis, RedisTransport)

# Use registered transport
MyMessage.config do
  transport SmartMessage::Transport.create(:redis, url: "redis://localhost")
end
```

## Thread Safety & Concurrency

### Thread Pool Management

The dispatcher uses `Concurrent::CachedThreadPool` for processing:

```ruby
# Each message processing happens in its own thread
@router_pool.post do
  # Message processing happens here
  target_class.constantize.process(header, payload)
end
```

### Thread Safety Considerations

1. **Message Instances**: Each message is processed in isolation
2. **Shared State**: Avoid shared mutable state in message classes
3. **Statistics**: Thread-safe statistics collection via `SimpleStats`
4. **Graceful Shutdown**: Automatic cleanup on process exit

### Monitoring Thread Pools

```ruby
dispatcher = SmartMessage::Dispatcher.new
status = dispatcher.status

puts "Running: #{status[:running]}"
puts "Queue length: #{status[:queue_length]}"
puts "Completed tasks: #{status[:completed_task_count]}"
```

## Error Handling Architecture

### Exception Isolation

Processing exceptions are isolated to prevent cascade failures:

```ruby
begin
  target_class.constantize.process(header, payload)
rescue Exception => e
  # Log error but don't crash the dispatcher
  # TODO: Add proper exception logging
end
```

### Custom Error Types

SmartMessage defines specific error types for different failure modes:

```ruby
module SmartMessage::Errors
  class TransportNotConfigured < RuntimeError; end
  class SerializerNotConfigured < RuntimeError; end
  class NotImplemented < RuntimeError; end
  class ReceivedMessageNotSubscribed < RuntimeError; end
  class UnknownMessageClass < RuntimeError; end
end
```

## Statistics & Monitoring

### Built-in Statistics

SmartMessage automatically collects processing statistics:

```ruby
# Statistics are collected for:
SS.add(message_class, 'publish')
SS.add(message_class, process_method, 'routed')

# Access statistics
puts SS.stat
puts SS.get("MyMessage", "publish")
```

### Monitoring Points

1. **Message Publishing**: Count of published messages per class
2. **Message Routing**: Count of routed messages per processor
3. **Thread Pool**: Queue length, completed tasks, running status
4. **Transport Status**: Connection status, message counts

## Configuration Architecture

### Configuration Hierarchy

1. **Class-level defaults**: Set via `MyMessage.config`
2. **Instance-level overrides**: Set via `message.config`
3. **Runtime configuration**: Dynamic plugin switching

### Configuration Objects

Configuration uses method-based DSL:

```ruby
config do
  transport MyTransport.new(option1: value1)
  serializer MySerializer.new(option2: value2)
  logger MyLogger.new(level: :debug)
end
```

### Plugin Resolution

When a message needs a plugin:

1. Check instance-level configuration
2. Fall back to class-level configuration
3. Raise error if not configured

```ruby
def transport
  @transport || @@transport || raise(Errors::TransportNotConfigured)
end
```

This architecture provides flexibility while maintaining clear fallback behavior.