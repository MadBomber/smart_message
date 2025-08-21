# Message Filtering

SmartMessage provides powerful message filtering capabilities that allow subscribers to receive only messages that match specific criteria. This enables sophisticated routing patterns for microservices architectures, environment-based deployment, and fine-grained message processing control.

## Overview

Message filtering works at the subscription level, allowing you to specify criteria that incoming messages must match before being routed to your handlers. Filters support:

- **Exact string matching** for precise service identification
- **Regular expression patterns** for flexible service groups and environments
- **Arrays combining strings and regexps** for complex matching scenarios
- **Multi-criteria filtering** using both `from` and `to` constraints

## Filter Dimensions

Messages can be filtered on two main dimensions:

### `from:` - Message Sender Filtering
Filter messages based on who sent them:

```ruby
# Exact sender
PaymentService.subscribe(from: 'payment-gateway')

# Pattern matching for sender groups
PaymentService.subscribe(from: /^payment-.*/)

# Multiple specific senders
AdminService.subscribe(from: ['admin', 'system', 'monitoring'])
```

### `to:` - Message Recipient Filtering  
Filter messages based on their intended recipient:

```ruby
# Exact recipient
OrderService.subscribe(to: 'order-processor')

# Environment-based routing
DevService.subscribe(to: /^(dev|staging)-.*/)
ProdService.subscribe(to: /^prod-.*/)

# Multiple target patterns
ApiService.subscribe(to: [/^api-.*/, /^web-.*/, 'gateway'])
```

### `broadcast:` - Broadcast Message Filtering
Filter for broadcast messages (messages with `to: nil`):

```ruby
# Only broadcast messages
NotificationService.subscribe(broadcast: true)

# Broadcast OR directed messages (OR logic)
AlertService.subscribe(broadcast: true, to: 'alert-service')
```

## Filter Types

### String Filters (Exact Match)

String filters match exactly:

```ruby
class OrderMessage < SmartMessage::Base
  # Configure message
end

# Subscribe to messages from exactly 'payment-service'
OrderMessage.subscribe(from: 'payment-service')

# Subscribe to messages directed to exactly 'order-processor'
OrderMessage.subscribe(to: 'order-processor')

# Combined exact matching
OrderMessage.subscribe(from: 'admin', to: 'order-service')
```

### Regular Expression Filters (Pattern Match)

Regex filters provide flexible pattern matching:

```ruby
# Environment-based routing
OrderMessage.subscribe(to: /^(dev|staging)-.*/)  # dev-api, staging-worker, etc.
OrderMessage.subscribe(to: /^prod-.*/)           # prod-api, prod-worker, etc.

# Service type routing  
OrderMessage.subscribe(from: /^payment-.*/)      # payment-gateway, payment-processor
OrderMessage.subscribe(from: /^(api|web)-.*/)    # api-server, web-frontend

# Complex patterns
OrderMessage.subscribe(from: /^admin-(dev|staging)-.+/)  # admin-dev-panel, admin-staging-api
```

### Array Filters (Multiple Options)

Arrays allow combining exact strings and regex patterns:

```ruby
# Multiple exact matches
OrderMessage.subscribe(from: ['admin', 'system', 'monitoring'])

# Mixed strings and patterns
OrderMessage.subscribe(from: [
  'admin',              # Exact match
  /^system-.*/, # Pattern match
  'legacy-service'      # Another exact match
])

# Multiple patterns
OrderMessage.subscribe(to: [
  /^api-.*/,     # All API services  
  /^web-.*/,     # All web services
  'gateway'      # Plus specific gateway
])
```

### Combined Filters (Multi-Criteria)

Combine `from`, `to`, and `broadcast` filters:

```ruby
# Admin services to production environments only
OrderMessage.subscribe(
  from: /^admin-.*/, 
  to: /^prod-.*/
)

# Specific senders to multiple recipient types
OrderMessage.subscribe(
  from: ['payment-gateway', 'billing-service'],
  to: [/^order-.*/, /^fulfillment-.*/]
)

# Complex routing scenarios
OrderMessage.subscribe(
  from: /^(admin|system)-.*/,
  to: ['critical-service', /^prod-.*/]
)
```

## Use Cases and Patterns

### Environment-Based Routing

Route messages based on deployment environments:

```ruby
# Development services
class DevOrderProcessor < SmartMessage::Base
  # Only receive messages to dev/staging environments
  DevOrderProcessor.subscribe(to: /^(dev|staging)-.*/)
end

# Production services  
class ProdOrderProcessor < SmartMessage::Base
  # Only receive messages to production environments
  ProdOrderProcessor.subscribe(to: /^prod-.*/)
end

# Cross-environment admin tools
class AdminDashboard < SmartMessage::Base
  # Receive admin messages from any environment
  AdminDashboard.subscribe(from: /^admin-.*/)
end
```

### Service Pattern Routing

Route based on service naming conventions:

```ruby
# Payment services ecosystem
class PaymentProcessor < SmartMessage::Base
  # Receive from all payment-related services
  PaymentProcessor.subscribe(from: /^payment-.*/)
end

# API layer services
class ApiGateway < SmartMessage::Base
  # Receive from web frontends and mobile apps
  ApiGateway.subscribe(from: /^(web|mobile|api)-.*/)
end

# Monitoring and alerting
class MonitoringService < SmartMessage::Base
  # Receive from all system monitoring components
  MonitoringService.subscribe(from: /^(system|monitor|health)-.*/)
end
```

### Administrative and Security Routing

Route administrative and security messages:

```ruby
# Security monitoring
class SecurityService < SmartMessage::Base
  # Admin + security services + any system monitoring
  SecurityService.subscribe(from: ['admin', /^security-.*/, /^system-monitor.*/])
end

# Audit logging
class AuditService < SmartMessage::Base
  # Capture all admin actions across environments
  AuditService.subscribe(from: /^admin-.*/)
end

# Operations dashboard
class OpsDashboard < SmartMessage::Base
  # Operational messages + broadcasts
  OpsDashboard.subscribe(
    broadcast: true,
    from: /^(ops|admin|system)-.*/
  )
end
```

### Gateway and Transformation Patterns

Filter for message transformation and routing:

```ruby
# Message format gateway
class FormatGateway < SmartMessage::Base
  # Receive legacy format messages for transformation
  FormatGateway.subscribe(from: ['legacy-system', /^old-.*/, 'mainframe'])
  
  def self.process(header, payload)
    # Transform and republish
    transformed = transform_legacy_format(payload)
    ModernMessage.new(transformed).publish
  end
end

# Environment promotion gateway
class PromotionGateway < SmartMessage::Base
  # Receive staging-approved messages for prod promotion
  PromotionGateway.subscribe(
    from: /^staging-.*/, 
    to: 'promotion-queue'
  )
  
  def self.process(header, payload)
    # Republish to production
    data = JSON.parse(payload)
    republish_to_production(data)
  end
end
```

## Filter Validation

SmartMessage validates filter parameters at subscription time to prevent runtime errors:

### Valid Filter Types

```ruby
# String filters
MyMessage.subscribe(from: 'service-name')

# Regex filters  
MyMessage.subscribe(from: /^service-.*/)

# Array filters with strings and regexes
MyMessage.subscribe(from: ['exact-service', /^pattern-.*/, 'another-service'])

# Combined filters
MyMessage.subscribe(from: /^admin-.*/, to: ['service-a', /^prod-.*/])
```

### Invalid Filter Types

These will raise `ArgumentError` at subscription time:

```ruby
# Invalid primitive types
MyMessage.subscribe(from: 123)                    # Numbers not allowed
MyMessage.subscribe(from: true)                   # Booleans not allowed  
MyMessage.subscribe(from: {key: 'value'})         # Hashes not allowed

# Invalid array elements
MyMessage.subscribe(from: ['valid', 123])         # Mixed valid/invalid
MyMessage.subscribe(from: [/valid/, Object.new])  # Mixed valid/invalid
```

## Implementation Details

### Filter Processing

Internally, filters are processed by the dispatcher's `message_matches_filters?` method:

1. **Normalization**: String and Regexp values are converted to arrays
2. **Validation**: Array elements are validated to be String or Regexp only
3. **Matching**: For each filter array, check if message value matches any element:
   - String elements: exact equality (`filter == value`)
   - Regexp elements: pattern matching (`filter.match?(value)`)

### Performance Considerations

- **String matching**: Very fast hash-based equality
- **Regex matching**: Slightly slower but still performant for typical patterns
- **Array processing**: Linear scan through filter array (typically small)
- **Filter caching**: Normalized filters are cached in subscription objects

### Memory Usage

- Filter arrays are stored per subscription
- Regex objects are shared (Ruby optimizes identical regex literals)
- No dynamic regex compilation during message processing

## Testing Filtered Subscriptions

### Basic Filter Testing

```ruby
class FilterTest < Minitest::Test
  def setup
    @transport = SmartMessage::Transport.create(:memory, auto_process: true)
    TestMessage.config do
      transport @transport
      serializer SmartMessage::Serializer::Json.new
    end
    TestMessage.unsubscribe!
  end

  def test_string_filter
    TestMessage.subscribe(from: 'payment-service')
    
    # Should match
    message = TestMessage.new(data: 'test')
    message.from('payment-service')
    message.publish
    
    # Should not match
    message = TestMessage.new(data: 'test')  
    message.from('user-service')
    message.publish
    
    # Verify only one message was processed
    assert_equal 1, processed_message_count
  end

  def test_regex_filter
    TestMessage.subscribe(from: /^payment-.*/)
    
    # Should match
    ['payment-gateway', 'payment-processor'].each do |sender|
      message = TestMessage.new(data: 'test')
      message.from(sender)
      message.publish
    end
    
    # Should not match
    message = TestMessage.new(data: 'test')
    message.from('user-service')
    message.publish
    
    # Verify two messages were processed
    assert_equal 2, processed_message_count
  end

  def test_combined_filter
    TestMessage.subscribe(from: /^admin-.*/, to: /^prod-.*/)
    
    # Should match
    message = TestMessage.new(data: 'test')
    message.from('admin-panel')
    message.to('prod-api')
    message.publish
    
    # Should not match (wrong from)
    message = TestMessage.new(data: 'test')
    message.from('user-panel')
    message.to('prod-api')
    message.publish
    
    # Should not match (wrong to)
    message = TestMessage.new(data: 'test')
    message.from('admin-panel')
    message.to('dev-api')
    message.publish
    
    # Verify only one message was processed
    assert_equal 1, processed_message_count
  end
end
```

### Performance Testing

```ruby
def test_filter_performance
  # Setup large number of subscriptions with different filters
  1000.times do |i|
    TestMessage.subscribe("TestMessage.handler_#{i}", from: "service-#{i}")
  end
  
  start_time = Time.now
  
  # Publish many messages
  100.times do |i|
    message = TestMessage.new(data: i)
    message.from("service-#{i % 10}")  # Will match some filters
    message.publish
  end
  
  processing_time = Time.now - start_time
  
  # Verify performance is acceptable
  assert processing_time < 1.0, "Filter processing took too long: #{processing_time}s"
end
```

## Migration Guide

### Upgrading from String-Only Filters

If you're upgrading from a version that only supported string filters:

```ruby
# Old (still works)
MyMessage.subscribe(from: 'exact-service')
MyMessage.subscribe(from: ['service-a', 'service-b'])

# New capabilities
MyMessage.subscribe(from: /^service-.*/)                    # Regex patterns
MyMessage.subscribe(from: ['exact', /^pattern-.*/])         # Mixed arrays
MyMessage.subscribe(from: /^admin-.*/, to: /^prod-.*/)      # Combined criteria
```

### Error Handling Changes

Previous versions may have failed silently with invalid filters. The new implementation validates at subscription time:

```ruby
# This will now raise ArgumentError instead of failing silently
begin
  MyMessage.subscribe(from: 123)  # Invalid type
rescue ArgumentError => e
  puts "Filter validation failed: #{e.message}"
end
```

## Next Steps

- [Dispatcher Documentation](dispatcher.md) - How filtering integrates with message routing
- [Entity Addressing](addressing.md) - Understanding `from`, `to`, and `reply_to` fields  
- [Examples](examples.md) - Complete working examples with filtering
- [Testing Guide](testing.md) - Best practices for testing filtered subscriptions