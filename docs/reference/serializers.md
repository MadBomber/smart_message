# Transport-Based Serialization

In SmartMessage's architecture, serialization is handled at the transport level rather than being configured for individual messages. Each transport manages its own optimal serialization format, eliminating the need for separate serializer configuration.

## Overview

Transport-based serialization provides:
- **Automatic Format Selection**: Each transport chooses its optimal serialization format
- **Simplified Configuration**: No need to configure serializers separately
- **Format Optimization**: Transports can choose the best format for their medium
- **Consistent Behavior**: All messages using a transport share the same serialization format

## Transport Serialization Formats

### Memory Transport
- **Format**: No serialization (objects passed directly)
- **Use case**: Testing and development where no network transmission occurs
- **Performance**: Fastest possible (no encoding/decoding overhead)

```ruby
# Memory transport - no serialization needed
transport = SmartMessage::Transport::MemoryTransport.new
```

### STDOUT Transport
- **Format**: JSON (human-readable)
- **Use case**: Debugging, development logging, message inspection
- **Features**: Pretty-printed output for easy reading

```ruby
# STDOUT transport - uses JSON for readability
transport = SmartMessage::Transport::StdoutTransport.new(
  format: :pretty  # or :json for compact format
)
```

### Redis Transport
- **Format**: MessagePack (primary), JSON (fallback)
- **Use case**: Production messaging where efficiency matters
- **Benefits**: Compact binary format reduces network overhead

```ruby
# Redis transport - automatically uses MessagePack if available
transport = SmartMessage::Transport::RedisTransport.new(
  url: 'redis://localhost:6379'
)
```

## How It Works

### Transport Serialization Process

1. **Message Publishing**: 
   ```ruby
   message = OrderMessage.new(order_id: "123", amount: 99.99)
   message.publish  # Transport handles serialization automatically
   ```

2. **Automatic Encoding**: Transport calls its serializer internally
   ```ruby
   # Inside transport.publish(message):
   serialized = transport.serializer.encode(message.to_hash)
   ```

3. **Message Receiving**: Transport deserializes automatically
   ```ruby
   # Inside transport.receive(serialized_data):
   data = transport.serializer.decode(serialized_data)
   message = MessageClass.new(data)
   ```

### Message Structure

All messages are serialized as flat hashes with the `_sm_header` property containing routing metadata:

```ruby
{
  _sm_header: {
    uuid: "...",
    message_class: "OrderMessage", 
    published_at: "2025-01-09T...",
    from: "order-service",
    to: "fulfillment-service",
    serializer: "SmartMessage::Serializer::Json"
  },
  order_id: "123",
  amount: 99.99,
  items: ["Widget A", "Widget B"]
}
```

## Custom Transport Serializers

You can specify a custom serializer when creating a transport:

```ruby
# Custom serializer for a transport
class MyCustomSerializer
  def encode(data_hash)
    # Your encoding logic here
    # Must return a string
  end

  def decode(serialized_string)
    # Your decoding logic here
    # Must return a hash
  end
end

# Use custom serializer with transport
transport = SmartMessage::Transport::RedisTransport.new(
  serializer: MyCustomSerializer.new,
  url: 'redis://localhost:6379'
)
```

## Built-in Serializer Classes

SmartMessage includes these serializer implementations that transports use internally:

### JSON Serializer
```ruby
SmartMessage::Serializer::Json.new
```
- Human-readable format
- Wide compatibility
- Used by STDOUT transport and as fallback

### MessagePack Serializer
```ruby
SmartMessage::Serializer::MessagePack.new
```
- Binary format for efficiency
- Smaller payload size
- Used by Redis transport when available

## Migration from Message-Level Serializers

If you were previously configuring serializers at the message level, here's how to migrate:

### Before (Message-Level Configuration)
```ruby
class OrderMessage < SmartMessage::Base
  property :order_id
  property :amount
  
  config do
    transport SmartMessage::Transport::RedisTransport.new
    serializer SmartMessage::Serializer::Json.new  # ❌ No longer needed
  end
end
```

### After (Transport-Level Serialization)
```ruby
class OrderMessage < SmartMessage::Base
  property :order_id
  property :amount
  
  config do
    # Transport automatically handles serialization
    transport SmartMessage::Transport::RedisTransport.new
  end
end

# Or specify custom serializer for transport
class OrderMessage < SmartMessage::Base
  property :order_id
  property :amount
  
  config do
    transport SmartMessage::Transport::RedisTransport.new(
      serializer: MyCustomSerializer.new
    )
  end
end
```

## Serialization Best Practices

### 1. Let Transports Choose
Let each transport use its optimal format:
- Memory: No serialization
- STDOUT: JSON for readability  
- Redis: MessagePack for efficiency

### 2. Custom Serializers
Only use custom serializers when you have specific requirements:
- Special data formats (XML, Protocol Buffers)
- Encryption/compression needs
- Legacy system compatibility

### 3. Testing
Test with actual transports to ensure serialization works correctly:

```ruby
RSpec.describe OrderMessage do
  it "serializes correctly with Redis transport" do
    transport = SmartMessage::Transport::RedisTransport.new
    message = OrderMessage.new(order_id: "123", amount: 99.99)
    
    # Test roundtrip serialization
    serialized = transport.encode_message(message)
    deserialized = transport.decode_message(serialized)
    
    expect(deserialized[:order_id]).to eq("123")
    expect(deserialized[:amount]).to eq(99.99)
  end
end
```

### 4. Error Handling
Transports handle serialization errors internally, but you can still catch them:

```ruby
begin
  message.publish
rescue SmartMessage::Errors::SerializationError => e
  logger.error "Failed to serialize message: #{e.message}"
end
```

## Performance Considerations

### Format Efficiency
- **MessagePack**: 20-30% more compact than JSON
- **JSON**: Human-readable but larger payload
- **Memory**: No serialization overhead

### Network Optimization
- Redis transport automatically uses MessagePack when available
- Falls back to JSON if MessagePack gem is not installed
- STDOUT uses JSON for debugging clarity

### Monitoring
Each transport logs its serializer choice:
```
[SmartMessage::Transport::RedisTransport] Using serializer: SmartMessage::Serializer::MessagePack
```

## Next Steps

- [Transports](transports.md) - Available transport implementations
- [Configuration](../getting-started/quick-start.md) - Setting up transports
- [Examples](../getting-started/examples.md) - Real-world usage patterns