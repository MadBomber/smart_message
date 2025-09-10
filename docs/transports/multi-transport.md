# Multi-Transport Publishing

**Send messages to multiple transports simultaneously for redundancy, integration, and migration scenarios.**

SmartMessage supports configuring messages with multiple transports, enabling sophisticated messaging patterns where a single `publish()` operation can deliver messages across different transport systems simultaneously.

## Overview

Multi-transport publishing allows you to:

- **Redundancy**: Send critical messages to primary and backup systems
- **Integration**: Simultaneously deliver to production queues and logging/monitoring systems
- **Migration**: Gradually transition between transport systems without downtime
- **Fan-out**: Broadcast messages to multiple processing pipelines
- **Resilience**: Ensure message delivery succeeds as long as ANY transport is available

## Basic Configuration

Configure multiple transports by passing an array to the `transport` method:

```ruby
class OrderProcessingMessage < SmartMessage::Base
  property :order_id, required: true
  property :customer_id, required: true
  property :amount, required: true
  
  # Configure multiple transports
  transport [
    SmartMessage::Transport.create(:redis_queue, url: 'redis://primary:6379'),
    SmartMessage::Transport.create(:redis, url: 'redis://backup:6379'),
    SmartMessage::Transport::StdoutTransport.new(format: :json)
  ]
end

# Publishing sends to ALL configured transports
message = OrderProcessingMessage.new(
  order_id: "ORD-12345", 
  customer_id: "CUST-789", 
  amount: 149.99
)

message.publish  # ✅ Publishes to Redis Queue, Redis Pub/Sub, and STDOUT
```

## Transport Introspection

SmartMessage provides utility methods to inspect and manage transport configurations:

```ruby
# Check transport configuration
puts message.multiple_transports?  # => true
puts message.single_transport?     # => false
puts message.transports.length     # => 3

# Access individual transports
message.transports.each_with_index do |transport, index|
  puts "Transport #{index}: #{transport.class.name}"
end

# Get primary transport (first in array) for backward compatibility
primary = message.transport  # Returns first transport
```

## Instance-Level Overrides

You can override class-level multi-transport configuration at the instance level:

```ruby
class MonitoringMessage < SmartMessage::Base
  property :metric, required: true
  
  # Class-level: send to monitoring and backup
  transport [
    SmartMessage::Transport.create(:redis, url: 'redis://monitoring:6379'),
    SmartMessage::Transport.create(:redis, url: 'redis://backup:6379')
  ]
end

# Instance-level override for testing
test_message = MonitoringMessage.new(metric: "cpu_usage: 85%")
test_message.transport(SmartMessage::Transport::StdoutTransport.new)

puts test_message.single_transport?  # => true (overridden)
test_message.publish  # Only goes to STDOUT
```

## Error Handling and Resilience

Multi-transport publishing is designed to be resilient:

### Partial Failures

When some transports succeed and others fail, publishing continues:

```ruby
class CriticalAlert < SmartMessage::Base
  property :alert_text, required: true
  
  transport [
    ReliableTransport.new,      # ✅ Succeeds
    FailingTransport.new,       # ❌ Fails
    BackupTransport.new         # ✅ Succeeds  
  ]
end

alert = CriticalAlert.new(alert_text: "Database connection lost")
alert.publish  # ✅ Succeeds! 2 out of 3 transports work

# Logs will show:
# [INFO] Published: CriticalAlert via ReliableTransport, BackupTransport  
# [WARN] Failed transports for CriticalAlert: FailingTransport
```

### Complete Failures

Only when ALL transports fail does publishing raise an error:

```ruby
class AllFailingMessage < SmartMessage::Base
  property :data
  
  transport [
    FailingTransport.new,       # ❌ Fails
    AnotherFailingTransport.new # ❌ Fails
  ]
end

message = AllFailingMessage.new(data: "test")

begin
  message.publish
rescue SmartMessage::Errors::PublishError => e
  puts e.message  # "All transports failed: FailingTransport: connection error; AnotherFailingTransport: timeout"
end
```

### Error Logging

Multi-transport publishing provides comprehensive error logging:

```ruby
# Example log output during partial failure:
[DEBUG] About to call transport.publish on RedisTransport
[DEBUG] transport.publish completed on RedisTransport
[ERROR] Transport FailingTransport failed: StandardError - Connection timeout
[DEBUG] About to call transport.publish on StdoutTransport  
[DEBUG] transport.publish completed on StdoutTransport
[INFO]  Published: MyMessage via RedisTransport, StdoutTransport
[WARN]  Failed transports for MyMessage: FailingTransport
```

## Common Use Cases

### 1. High-Availability Critical Messages

Ensure critical business messages reach their destination even if primary systems fail:

```ruby
class PaymentProcessedMessage < SmartMessage::Base
  property :payment_id, required: true
  property :amount, required: true
  property :status, required: true
  
  # Primary processing + backup + audit trail
  transport [
    SmartMessage::Transport.create(:redis_queue, 
      url: 'redis://primary-cluster:6379',
      queue_prefix: 'payments'
    ),
    SmartMessage::Transport.create(:redis,
      url: 'redis://backup-cluster:6380'  
    ),
    SmartMessage::Transport::StdoutTransport.new(
      output: '/var/log/payments.log',
      format: :json
    )
  ]
end
```

### 2. Development and Production Dual Publishing

Send messages to both production and development environments during migration:

```ruby
class UserRegistrationMessage < SmartMessage::Base  
  property :user_id, required: true
  property :email, required: true
  
  # Dual publishing during migration
  transport [
    SmartMessage::Transport.create(:redis, 
      url: ENV['PRODUCTION_REDIS_URL']
    ),
    SmartMessage::Transport.create(:redis_queue,
      url: ENV['NEW_SYSTEM_REDIS_URL'],
      queue_prefix: 'migration'
    )
  ]
end
```

### 3. Monitoring and Alerting Integration

Combine business processing with operational monitoring:

```ruby
class OrderFailureMessage < SmartMessage::Base
  property :order_id, required: true  
  property :error_message, required: true
  property :customer_impact, required: true
  
  transport [
    # Business processing
    SmartMessage::Transport.create(:redis_queue,
      url: 'redis://orders:6379'
    ),
    
    # Operations monitoring  
    SmartMessage::Transport.create(:webhook,
      url: 'https://monitoring.company.com/alerts'
    ),
    
    # Development debugging
    SmartMessage::Transport::StdoutTransport.new(format: :pretty)
  ]
end
```

### 4. A/B Testing and Feature Rollouts

Send messages to old and new systems during feature rollouts:

```ruby
class AnalyticsEventMessage < SmartMessage::Base
  property :event_type, required: true
  property :user_id, required: true
  property :metadata, default: {}
  
  transport [
    # Existing analytics pipeline (stable)
    SmartMessage::Transport.create(:redis, 
      url: 'redis://analytics-v1:6379'
    ),
    
    # New analytics pipeline (testing)  
    SmartMessage::Transport.create(:redis_queue,
      url: 'redis://analytics-v2:6379',
      queue_prefix: 'beta'
    )
  ]
end
```

## Performance Considerations

### Sequential Processing

Transports are processed sequentially in the order configured:

```ruby
# Order matters for performance
transport [
  FastMemoryTransport.new,      # Processed first (fast)
  SlowNetworkTransport.new,     # Processed second (slow) 
  AnotherFastTransport.new      # Processed third (waits for slow)
]
```

**Recommendation**: Place fastest/most critical transports first.

### Transport Independence

Each transport failure is isolated and doesn't affect others:

```ruby
transport [
  ReliableTransport.new,        # Always succeeds
  UnreliableTransport.new,      # May fail, doesn't affect others
  BackupTransport.new           # Provides redundancy
]
```

### Memory Usage

Each transport instance maintains its own connection and state:

```ruby
# Each transport creates its own connection pool
transport [
  SmartMessage::Transport.create(:redis, url: 'redis://server1:6379'),  
  SmartMessage::Transport.create(:redis, url: 'redis://server2:6379'),
  SmartMessage::Transport.create(:redis, url: 'redis://server3:6379')   
]
# Total: 3 Redis connection pools
```

## Best Practices

### 1. Limit Transport Count

Don't configure excessive transports as this impacts performance:

```ruby
# ✅ Good: 2-4 transports for specific purposes
transport [
  PrimaryTransport.new,
  BackupTransport.new, 
  MonitoringTransport.new
]

# ❌ Avoid: Too many transports
transport [
  Transport1.new, Transport2.new, Transport3.new,
  Transport4.new, Transport5.new, Transport6.new  # Overkill
]
```

### 2. Group by Purpose

Organize transports by their intended purpose:

```ruby
class BusinessMessage < SmartMessage::Base
  transport [
    # Core business processing
    SmartMessage::Transport.create(:redis_queue, url: primary_redis_url),
    
    # Operational monitoring  
    SmartMessage::Transport::StdoutTransport.new(
      output: '/var/log/business-events.log'
    ),
    
    # Disaster recovery backup
    SmartMessage::Transport.create(:redis, url: backup_redis_url)
  ]
end
```

### 3. Environment-Specific Configuration

Use environment variables for transport configuration:

```ruby
class ConfigurableMessage < SmartMessage::Base
  transport_configs = []
  
  # Always include primary transport
  transport_configs << SmartMessage::Transport.create(:redis_queue,
    url: ENV['PRIMARY_REDIS_URL']
  )
  
  # Add backup transport in production
  if Rails.env.production?
    transport_configs << SmartMessage::Transport.create(:redis,
      url: ENV['BACKUP_REDIS_URL'] 
    )
  end
  
  # Add stdout transport in development
  if Rails.env.development? 
    transport_configs << SmartMessage::Transport::StdoutTransport.new
  end
  
  transport transport_configs
end
```

### 4. Health Monitoring

Monitor the health of your multi-transport setup:

```ruby
class HealthCheckMessage < SmartMessage::Base
  property :timestamp, default: -> { Time.now }
  
  transport [
    PrimaryTransport.new,
    BackupTransport.new
  ]
  
  # Class method to check transport health
  def self.health_check
    test_message = new(timestamp: Time.now)
    
    begin
      test_message.publish
      { status: 'healthy', transports: 'all_operational' }
    rescue SmartMessage::Errors::PublishError => e
      { status: 'degraded', error: e.message }
    end
  end
end
```

## Migration Strategies

### Gradual Migration

When migrating from one transport to another:

```ruby
class MigrationMessage < SmartMessage::Base
  
  # Phase 1: Dual publishing
  transport [
    OldTransport.new,      # Keep existing system running
    NewTransport.new       # Start sending to new system
  ]
  
  # Phase 2: Monitor and validate new system
  # Phase 3: Remove old transport when confident
end
```

### Blue-Green Deployment

Support blue-green deployments with transport switching:

```ruby
class DeploymentMessage < SmartMessage::Base
  def self.configure_for_deployment(color)
    case color
    when :blue
      transport BlueEnvironmentTransport.new
    when :green  
      transport GreenEnvironmentTransport.new
    when :both
      transport [
        BlueEnvironmentTransport.new,
        GreenEnvironmentTransport.new
      ]
    end
  end
end
```

## Troubleshooting

### Common Issues

**Issue**: Publishing seems slow
```ruby
# Check transport order - slow transports block subsequent ones
transport [
  SlowTransport.new,     # ❌ Blocks others
  FastTransport.new      # Must wait for slow one
]

# Solution: Reorder with fastest first
transport [
  FastTransport.new,     # ✅ Completes quickly  
  SlowTransport.new      # Others don't wait
]
```

**Issue**: Partial failures not logged
```ruby
# Ensure proper logging configuration
SmartMessage.configure do |config|
  config.logger.level = :debug  # Show all transport operations
end
```

**Issue**: All transports failing unexpectedly
```ruby
# Test each transport individually
message.transports.each_with_index do |transport, index|
  begin
    transport.publish(message)
    puts "Transport #{index} (#{transport.class.name}): ✅ Success"
  rescue => e
    puts "Transport #{index} (#{transport.class.name}): ❌ Failed - #{e.message}"
  end
end
```

## See Also

- [Transport Layer Overview](../reference/transports.md)
- [Redis Queue Transport](redis-transport.md) 
- [Memory Transport](memory-transport.md)
- [Error Handling and Dead Letter Queues](../reference/dead-letter-queue.md)
- [Performance Optimization](../development/performance.md)