# Transport Selection Guide

Choosing the right transport for your SmartMessage application is crucial for performance, reliability, and maintainability. This guide provides comprehensive information about each available transport and decision matrices to help you select the optimal transport configuration.

## Available Transports

### Memory Transport
**In-memory message storage for development and testing**

- **Type**: In-memory queue with optional auto-processing
- **Best For**: Unit testing, development, rapid prototyping, message inspection
- **Key Features**: 
  - No external dependencies
  - Thread-safe operations
  - Message inspection capabilities
  - Configurable memory limits
  - Fastest performance (~0.01ms latency)
- **Limitations**: Single-process only, no persistence, memory usage grows with volume
- **Use Cases**: Unit tests, development debugging, in-memory message queuing

### Redis Transport
**Production-ready Redis pub/sub for distributed messaging**

- **Type**: Redis pub/sub with broadcast delivery
- **Best For**: Production messaging, microservices communication, real-time applications
- **Key Features**:
  - Distributed messaging support
  - Automatic reconnection handling
  - High throughput (80K+ messages/second)
  - Low latency (~1ms)
  - Thread-based subscriber model
- **Limitations**: No message persistence, no pattern matching, all subscribers receive all messages
- **Use Cases**: Production systems, scalable architectures, service-to-service messaging

### STDOUT Transport
**Console and file output with multiple formatting options**

- **Type**: Output-only transport with formatting capabilities
- **Best For**: Development debugging, application logging, message tracing, integration testing
- **Key Features**:
  - Three output formats (`:pretty`, `:jsonl`, `:json`)
  - Console or file output
  - Optional loopback processing
  - Human-readable pretty printing
  - Thread-safe file operations
- **Limitations**: Not suitable for production messaging, single output destination
- **Use Cases**: Development debugging, structured logging, message flow tracing

### File Transport
**Base class for file-based messaging**

- **Type**: Abstract base class for file-based transports
- **Best For**: Custom file-based transport implementations, message archiving
- **Key Features**:
  - Automatic directory creation
  - Thread-safe file operations
  - Message serialization handling
  - Extensible architecture for custom transports
- **Limitations**: Rarely used directly, requires custom implementation
- **Use Cases**: Custom transport development, message persistence, audit trails

### Multi-Transport Publishing
**Simultaneous publishing to multiple transports**

- **Type**: Configuration pattern for publishing to multiple destinations
- **Best For**: High availability, migration scenarios, monitoring integration, redundancy
- **Key Features**:
  - Publish to multiple transports with single `publish()` call
  - Resilient to partial failures
  - Sequential processing with error isolation
  - Transport introspection methods
- **Limitations**: Sequential processing can impact performance, memory usage scales with transport count
- **Use Cases**: Critical message redundancy, gradual migration, operational monitoring

## Transport Selection Matrix

### By Development Phase

| Phase | Primary Transport | Secondary Transport | Use Case |
|-------|------------------|-------------------|----------|
| **Unit Testing** | Memory | - | Fast, isolated, inspectable |
| **Development** | STDOUT (pretty) | Memory (loopback) | Human-readable debugging |
| **Integration Testing** | STDOUT (jsonl) | Memory | Structured output, verification |
| **Staging** | Redis | STDOUT (file) | Production-like with logging |
| **Production** | Redis | Multi-transport | Scalable with redundancy |

### By Use Case

| Use Case | Recommended Transport | Configuration | Rationale |
|----------|----------------------|---------------|-----------|
| **Unit Tests** | Memory | `auto_process: true` | No dependencies, fast, inspectable |
| **Development Debugging** | STDOUT | `format: :pretty, loopback: true` | Human-readable with local processing |
| **Application Logging** | STDOUT | `format: :jsonl, file_path: 'app.log'` | Structured logs for analysis |
| **Message Tracing** | STDOUT | `format: :json, file_path: '/tmp/trace.log'` | Compact format for debugging |
| **Production Messaging** | Redis | `url: ENV['REDIS_URL']` | Distributed, reliable, scalable |
| **Critical Messages** | Multi-transport | `[Redis, STDOUT(file), Redis(backup)]` | Redundancy and audit trail |
| **Migration Scenarios** | Multi-transport | `[OldTransport, NewTransport]` | Gradual transition |
| **Development→Production** | Environment-based | Switch based on `Rails.env` | Appropriate for each environment |

### By Architecture Pattern

#### Single Application (Monolith)
```ruby
# Development
transport: SmartMessage::Transport::StdoutTransport.new(format: :pretty)

# Production  
transport: SmartMessage::Transport::RedisTransport.new(url: ENV['REDIS_URL'])
```

#### Microservices Architecture
```ruby
# High-availability critical messages
transport: [
  SmartMessage::Transport::RedisTransport.new(url: primary_redis),
  SmartMessage::Transport::RedisTransport.new(url: backup_redis),
  SmartMessage::Transport::StdoutTransport.new(file_path: '/var/log/audit.log')
]
```

#### Event-Driven System
```ruby
# Events with monitoring
transport: [
  SmartMessage::Transport::RedisTransport.new(url: event_redis),
  SmartMessage::Transport::StdoutTransport.new(
    format: :jsonl, 
    file_path: '/var/log/events.log'
  )
]
```

## Decision Tree

### Step 1: Environment Classification
```
Are you in...?
├── Unit Testing → Memory Transport
├── Development → STDOUT Transport (pretty format)  
├── Integration Testing → STDOUT Transport (jsonl format)
└── Production → Continue to Step 2
```

### Step 2: Message Criticality (Production)
```
How critical are your messages?
├── Low criticality → Redis Transport (single)
├── Medium criticality → Redis + STDOUT file logging
└── High criticality → Multi-transport (Redis primary + backup + audit)
```

### Step 3: Scale Requirements
```
Expected message volume?
├── Low (<1K/day) → Any transport suitable
├── Medium (1K-100K/day) → Redis Transport recommended
└── High (>100K/day) → Redis Transport + performance tuning
```

### Step 4: Integration Requirements
```
Need external integration?
├── Log aggregation → STDOUT Transport (jsonl to file)
├── Monitoring systems → Multi-transport (Redis + STDOUT)
├── Audit requirements → Multi-transport with file logging
└── None → Single transport sufficient
```

## Configuration Examples

### Environment-Based Configuration
```ruby
class ApplicationMessage < SmartMessage::Base
  transport case Rails.env
            when 'test'
              SmartMessage::Transport::MemoryTransport.new(auto_process: true)
            when 'development'
              SmartMessage::Transport::StdoutTransport.new(
                format: :pretty,
                loopback: true
              )
            when 'staging'
              [
                SmartMessage::Transport::RedisTransport.new(url: ENV['REDIS_URL']),
                SmartMessage::Transport::StdoutTransport.new(
                  format: :jsonl,
                  file_path: '/var/log/staging.log'
                )
              ]
            when 'production'
              [
                SmartMessage::Transport::RedisTransport.new(url: ENV['PRIMARY_REDIS_URL']),
                SmartMessage::Transport::RedisTransport.new(url: ENV['BACKUP_REDIS_URL']),
                SmartMessage::Transport::StdoutTransport.new(
                  format: :jsonl,
                  file_path: '/var/log/production.log'
                )
              ]
            end
end
```

### Message-Type Based Selection
```ruby
# High-volume, low-criticality events
class UserActivityMessage < SmartMessage::Base
  transport SmartMessage::Transport::RedisTransport.new(url: ENV['REDIS_URL'])
end

# Critical business events
class PaymentProcessedMessage < SmartMessage::Base
  transport [
    SmartMessage::Transport::RedisTransport.new(url: ENV['PRIMARY_REDIS_URL']),
    SmartMessage::Transport::RedisTransport.new(url: ENV['BACKUP_REDIS_URL']),
    SmartMessage::Transport::StdoutTransport.new(
      format: :jsonl,
      file_path: '/var/log/payments.log'
    )
  ]
end

# Development/debugging messages
class DebugMessage < SmartMessage::Base
  transport SmartMessage::Transport::StdoutTransport.new(
    format: :pretty,
    loopback: true
  )
end
```

## Performance Considerations

### Latency Comparison
| Transport | Typical Latency | Best Use |
|-----------|----------------|----------|
| Memory | ~0.01ms | Unit tests, development |
| STDOUT | ~1ms | Logging, debugging |
| Redis | ~1ms | Production messaging |
| Multi-transport | Sum of individual transports | Critical messages |

### Throughput Comparison
| Transport | Throughput | Limiting Factor |
|-----------|------------|----------------|
| Memory | Highest | CPU and memory |
| STDOUT | Medium | I/O operations |
| Redis | High | Network and Redis performance |
| Multi-transport | Lowest individual transport | Sequential processing |

### Resource Usage
| Transport | Memory Usage | External Dependencies | Setup Complexity |
|-----------|--------------|----------------------|------------------|
| Memory | Grows with volume | None | Minimal |
| STDOUT | Minimal | None | Minimal |
| Redis | Low | Redis server | Medium |
| File | Minimal | None | Minimal |

## Migration Strategies

### Development to Production
```ruby
# Phase 1: Development (Memory/STDOUT)
transport: SmartMessage::Transport::MemoryTransport.new

# Phase 2: Integration Testing (STDOUT with file)
transport: SmartMessage::Transport::StdoutTransport.new(
  format: :jsonl,
  file_path: '/tmp/integration.log'
)

# Phase 3: Staging (Redis + logging)
transport: [
  SmartMessage::Transport::RedisTransport.new(url: staging_redis),
  SmartMessage::Transport::StdoutTransport.new(file_path: '/var/log/staging.log')
]

# Phase 4: Production (Multi-transport)
transport: [
  SmartMessage::Transport::RedisTransport.new(url: primary_redis),
  SmartMessage::Transport::RedisTransport.new(url: backup_redis)
]
```

### Transport Evolution
```ruby
# Start simple
class MyMessage < SmartMessage::Base
  transport SmartMessage::Transport::MemoryTransport.new
end

# Add logging
class MyMessage < SmartMessage::Base
  transport SmartMessage::Transport::StdoutTransport.new(format: :jsonl)
end

# Scale to production
class MyMessage < SmartMessage::Base
  transport SmartMessage::Transport::RedisTransport.new(url: ENV['REDIS_URL'])
end

# Add redundancy
class MyMessage < SmartMessage::Base
  transport [
    SmartMessage::Transport::RedisTransport.new(url: ENV['PRIMARY_REDIS']),
    SmartMessage::Transport::RedisTransport.new(url: ENV['BACKUP_REDIS'])
  ]
end
```

## Best Practices

### General Guidelines
1. **Start Simple**: Begin with Memory/STDOUT transports in development
2. **Match Environment**: Use appropriate transports for each environment
3. **Consider Criticality**: More critical messages need more redundant transports
4. **Monitor Performance**: Track latency and throughput in production
5. **Plan Migration**: Design transport evolution from development to production

### Transport-Specific
- **Memory**: Use in tests and development only, set reasonable message limits
- **STDOUT**: Use `:pretty` for development, `:jsonl` for structured logging
- **Redis**: Configure proper connection pooling and reconnection settings
- **Multi-transport**: Limit to 2-4 transports, order by speed/criticality

### Environment Configuration
- **Development**: Readable formats, loopback enabled for testing
- **Testing**: Fast, isolated transports with deterministic behavior
- **Staging**: Production-like configuration with additional logging
- **Production**: Redundant, monitored, with proper error handling

## Troubleshooting

### Common Issues

**Slow message publishing**
- Check multi-transport ordering (put fastest first)
- Verify Redis connection health
- Monitor file I/O performance

**Messages not appearing**
- Verify transport configuration matches environment
- Check Redis connectivity and permissions
- Ensure file paths are writable

**Memory issues**
- Set limits on Memory transport
- Monitor multi-transport memory usage
- Check for message accumulation in development

**Test failures**
- Use Memory transport for predictable test behavior
- Clear messages between tests
- Mock external transport dependencies

## Related Documentation

- [Multi-Transport Publishing](../transports/multi-transport.md) - Detailed multi-transport patterns
- [Memory Transport](../transports/memory-transport.md) - Development and testing transport
- [Redis Transport](../transports/redis-transport.md) - Production messaging transport
- [STDOUT Transport](../transports/stdout-transport.md) - Output and logging transport
- [File Transport](../transports/file-transport.md) - Base class for file-based transports
- [Transport Overview](../reference/transports.md) - Technical transport reference