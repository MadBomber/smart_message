# Redis Enhanced Transport Examples

This directory contains comprehensive examples demonstrating the advanced features of `SmartMessage::Transport::RedisEnhancedTransport`, which extends the basic Redis transport with RabbitMQ-style pattern matching and intelligent routing capabilities.

## 🚀 What is Redis Enhanced Transport?

The Redis Enhanced Transport is a powerful extension of the basic Redis transport that provides:

- **Pattern-based subscriptions** with wildcard support (`*` and `#`)
- **Fluent API** for building complex subscription patterns
- **Dual channel publishing** for backwards compatibility
- **Enhanced routing** with 3-part channel names: `message_type.from.to`
- **Convenience methods** for common subscription patterns

## 📁 Example Files

### 1. `enhanced_01_basic_patterns.rb` - Pattern Subscriptions Fundamentals

**Focus**: Basic pattern subscription capabilities

**Key Features Demonstrated**:
- Direct pattern subscriptions with wildcards
- Convenience subscription methods
- Enhanced vs. original channel publishing
- Pattern-based message filtering

**Run Example**:
```bash
ruby examples/redis_queue/enhanced_01_basic_patterns.rb
```

**Sample Patterns**:
- `ordermessage.*.*` - All order messages
- `*.payment_gateway.*` - All messages from payment gateway
- `alertmessage.*.*` - All alert messages

### 2. `enhanced_02_fluent_api.rb` - Fluent API for Complex Routing

**Focus**: Fluent API for building readable subscription patterns

**Key Features Demonstrated**:
- Chainable `.where().from().to().type()` syntax
- Complex multi-condition subscriptions
- Microservices communication patterns
- Pattern building and visualization

**Run Example**:
```bash
ruby examples/redis_queue/enhanced_02_fluent_api.rb
```

**Sample Fluent Patterns**:
```ruby
transport.where.from('web-app').to('user-service').subscribe
transport.where.type('AnalyticsEventMessage').from('web-app').subscribe
transport.where.from('monitoring').to('admin-panel').type('AdminAlertMessage').subscribe
```

### 3. `enhanced_03_dual_publishing.rb` - Backwards Compatibility Demo

**Focus**: Dual channel publishing and transport compatibility

**Key Features Demonstrated**:
- Publishing to both original and enhanced channels
- Backwards compatibility with basic Redis transport
- Cross-transport message communication
- Channel naming conventions

**Run Example**:
```bash
ruby examples/redis_queue/enhanced_03_dual_publishing.rb
```

**Publishing Behavior**:
- Enhanced transport → publishes to BOTH channels
- Basic transport → publishes to original channel only
- Both can receive messages from each other

### 4. `enhanced_04_advanced_routing.rb` - Complex Microservices Scenarios

**Focus**: Advanced routing patterns for complex architectures

**Key Features Demonstrated**:
- Dynamic routing based on message content
- Service-specific pattern matching
- Log aggregation and metrics collection routing
- Complex microservices communication

**Run Example**:
```bash
ruby examples/redis_queue/enhanced_04_advanced_routing.rb
```

**Advanced Scenarios**:
- API Gateway routing to multiple services
- Database query routing from different ORM layers
- Log level-based filtering and aggregation
- Metrics collection from monitoring agents

## 🔧 Prerequisites

1. **Redis Server**: Make sure Redis is running
   ```bash
   # macOS
   brew services start redis
   
   # Linux
   sudo service redis start
   ```

2. **Ruby Dependencies**: Install required gems
   ```bash
   bundle install
   ```

3. **SmartMessage**: Ensure you're in the SmartMessage project root

## 🌟 Key Concepts

### Enhanced Channel Format

Enhanced channels use a 3-part naming scheme:
```
message_type.from.to
```

Examples:
- `ordermessage.api_gateway.order_service`
- `paymentmessage.payment_service.bank_gateway`
- `alertmessage.monitoring.broadcast`

### Pattern Wildcards

- `*` - Matches exactly one segment
- `#` - Matches zero or more segments (Redis doesn't support this natively, but Enhanced Transport simulates it)

### Convenience Methods

```ruby
transport.subscribe_to_recipient('payment-service')     # *.*.payment-service
transport.subscribe_from_sender('api-gateway')          # *.api-gateway.*
transport.subscribe_to_type('OrderMessage')             # ordermessage.*.*
transport.subscribe_to_alerts                           # emergency.*.*, *alert*.*.*, etc.
transport.subscribe_to_broadcasts                       # *.*.broadcast
```

### Fluent API Pattern Building

```ruby
# Basic patterns
transport.where.from('service-a').subscribe              # *.service-a.*
transport.where.to('service-b').subscribe                # *.*.service-b
transport.where.type('MessageType').subscribe            # messagetype.*.*

# Combined patterns  
transport.where.from('api').to('db').subscribe           # *.api.db
transport.where.type('Order').from('web').subscribe      # order.web.*
```

## 🔍 Monitoring and Debugging

### View Active Patterns

Each example shows how to inspect active pattern subscriptions:

```ruby
pattern_subscriptions = transport.instance_variable_get(:@pattern_subscriptions)
pattern_subscriptions.each { |pattern| puts pattern }
```

### Redis Channel Monitoring

You can monitor Redis channels directly:

```bash
# Monitor all channels
redis-cli monitor

# List active channels
redis-cli pubsub channels "*"

# Monitor specific pattern
redis-cli psubscribe "ordermessage.*"
```

## 🆚 Enhanced vs Basic vs Queue Transports

| Feature | Basic Redis | Enhanced Redis | Redis Queue |
|---------|-------------|----------------|-------------|
| Channel Format | Class name only | `type.from.to` | Stream-based |
| Pattern Support | None | Wildcard patterns | RabbitMQ-style |
| Backwards Compatible | N/A | ✅ Yes | ❌ No |
| Fluent API | ❌ No | ✅ Yes | ✅ Yes |
| Persistent Messages | ❌ No | ❌ No | ✅ Yes |
| Load Balancing | ❌ No | ❌ No | ✅ Yes |

## 🎯 Use Cases

### When to Use Enhanced Transport

- **Microservices Architecture**: Need sophisticated routing between services
- **Legacy Compatibility**: Must work with existing basic Redis transport
- **Pattern-Based Routing**: Want RabbitMQ-style patterns without RabbitMQ
- **Development/Testing**: Need flexible routing for development environments

### When to Use Basic Transport

- **Simple Scenarios**: Basic pub/sub without complex routing
- **Minimal Overhead**: Want lightest-weight solution
- **Legacy Systems**: Already using basic transport

### When to Use Queue Transport

- **Production Systems**: Need message persistence and reliability
- **Load Balancing**: Multiple consumers processing messages
- **Enterprise Features**: Dead letter queues, consumer groups, etc.

## 🚀 Getting Started

1. Start with `enhanced_01_basic_patterns.rb` to understand fundamentals
2. Progress through `enhanced_02_fluent_api.rb` for advanced patterns  
3. Explore `enhanced_03_dual_publishing.rb` for compatibility
4. Study `enhanced_04_advanced_routing.rb` for complex scenarios

Each example is self-contained and includes detailed explanations of the concepts being demonstrated.

## 📝 Example Output

When you run the examples, you'll see detailed output showing:
- ✅ Subscription confirmations
- 📤 Message publishing notifications  
- 📦 Message processing with routing details
- 🔍 Active pattern listings
- 💡 Key insights and takeaways

The examples use emojis and clear formatting to make the output easy to follow and understand.

Happy messaging! 🎉