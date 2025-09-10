# Memory Transport Examples

This directory contains demonstration programs that use SmartMessage's **Memory Transport** and **Stdout Transport** (with loopback). These examples show the fundamentals of SmartMessage without requiring external dependencies like Redis or message queues.

## Transport Overview

The Memory and Stdout (with loopback) transports are ideal for:
- **Learning SmartMessage fundamentals**
- **Rapid prototyping and testing**
- **Single-process applications**
- **Development and debugging**

These transports keep all message routing in-memory within the current Ruby process.

## Example Programs

### 📋 01_message_deduplication_demo.rb
**Demonstrates:** Message deduplication patterns
**Transport:** MemoryTransport
- Shows how to prevent duplicate message processing
- Implements deduplication based on message IDs
- Tracks processed messages to avoid reprocessing
- Useful for ensuring idempotent message handling

### 🚨 02_dead_letter_queue_demo.rb  
**Demonstrates:** Dead letter queue error handling
**Transport:** Custom failing transport (extends Base)
- Simulates transport failures and message retry logic
- Shows dead letter queue pattern implementation
- Handles various failure scenarios (connection errors, timeouts)
- Demonstrates message recovery and error reporting

### 🛍️ 03_point_to_point_orders.rb
**Demonstrates:** Point-to-point messaging (1:1)
**Transport:** StdoutTransport with loopback
- Order processing system between OrderService and PaymentService
- Request/response message pattern
- Automatic serialization of complex order data by transport
- Bidirectional communication flow

### 📢 04_publish_subscribe_events.rb
**Demonstrates:** Publish-subscribe messaging (1:many)
**Transport:** StdoutTransport with loopback
- User event notification system
- Multiple subscribers (EmailService, SMSService, AuditService)
- Event-driven architecture
- Different services handling same events differently

### 💬 05_many_to_many_chat.rb  
**Demonstrates:** Many-to-many messaging patterns
**Transport:** StdoutTransport with loopback
- Multi-user chat room system
- Message broadcasting to multiple participants
- User presence and room management
- Complex message routing scenarios

### 🎨 06_pretty_print_demo.rb
**Demonstrates:** Message pretty-printing and debugging
**Transport:** None (utility demo)
- Shows SmartMessage's `pretty_print` method
- Formats complex nested message data
- Header and content display modes
- Useful for development and troubleshooting

### ⚡ 07_proc_handlers_demo.rb
**Demonstrates:** Proc-based message handlers
**Transport:** StdoutTransport with loopback  
- Custom Proc handlers for message processing
- Dynamic message routing
- Flexible handler assignment
- Lambda and block-based processors

### 📊 08_custom_logger_demo.rb
**Demonstrates:** Custom logging implementations
**Transport:** StdoutTransport with loopback
- Multiple logger types and configurations
- Custom logger classes
- Log filtering and formatting
- Integration with external logging systems

### ❌ 09_error_handling_demo.rb
**Demonstrates:** Error handling strategies
**Transport:** StdoutTransport with loopback
- Various error scenarios and recovery patterns
- Exception handling in message processors
- Error propagation and logging
- Graceful degradation techniques

### 🎯 10_entity_addressing_basic.rb
**Demonstrates:** Basic entity addressing
**Transport:** StdoutTransport with loopback
- Message routing by entity addresses
- Order processing with specific routing
- Customer and payment entity handling
- Address-based message filtering

### 🔍 11_entity_addressing_with_filtering.rb  
**Demonstrates:** Advanced entity addressing with filters
**Transport:** StdoutTransport with loopback
- Complex filtering patterns
- Regex-based address matching
- Multiple entity types and routing rules
- Advanced subscription filtering

### 🏢 12_regex_filtering_microservices.rb
**Demonstrates:** Microservices with regex filtering
**Transport:** StdoutTransport with loopback
- Service-to-service communication patterns
- Regular expression-based routing
- Environment-based filtering (dev/staging/prod)
- Microservices architecture simulation

### 📝 13_header_block_configuration.rb
**Demonstrates:** Header configuration with blocks
**Transport:** StdoutTransport
- Dynamic header configuration
- Block-based header modification
- Custom header fields
- Header inheritance patterns

### 🌍 14_global_configuration_demo.rb  
**Demonstrates:** Global SmartMessage configuration
**Transport:** StdoutTransport with loopback
- Global transport settings
- Configuration inheritance (serialization handled by transport)
- Default settings management
- Application-wide configuration patterns

### 📋 15_logger_demo.rb
**Demonstrates:** Logger configuration and usage
**Transport:** StdoutTransport
- Various logger configurations
- Log level management
- Custom log formatting
- Integration with SmartMessage lifecycle

## Getting Started

To run any example:

```bash
cd examples/memory
ruby 01_message_deduplication_demo.rb
```

Most examples are self-contained and will demonstrate their concepts through console output.

## Key Learning Points

1. **In-Memory Processing**: All examples run within a single Ruby process
2. **No External Dependencies**: No Redis, database, or message broker required  
3. **Immediate Feedback**: Console output shows message flow in real-time
4. **Development Friendly**: Perfect for learning and experimentation
5. **Pattern Foundation**: Concepts apply to all SmartMessage transports

## Next Steps

After mastering these memory-based examples, explore:
- **[Redis Examples](../redis/)** - For distributed messaging
- **[Redis Queue Examples](../redis_queue/)** - For reliable message queuing
- **[Redis Enhanced Examples](../redis_enhanced/)** - For advanced Redis patterns

These memory examples provide the foundation for understanding SmartMessage's core concepts before moving to production-ready transports.