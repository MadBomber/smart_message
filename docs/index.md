# SmartMessage Documentation

<table border="0">
<tr>
<td width="30%" valign="top">
  <img src="assets/smart_message.jpg" alt="SmartMessage Logo" width="200" />
</td>
<td width="70%" valign="top">

**SmartMessage** is a powerful Ruby framework that transforms ordinary messages into intelligent, self-aware entities capable of routing themselves, validating their contents, and executing business logic. By abstracting away the complexities of transport mechanisms (Redis, RabbitMQ, Kafka) and serialization formats (JSON, MessagePack), SmartMessage lets you focus on what matters: your business logic.

Think of SmartMessage as ActiveRecord for messaging - just as ActiveRecord frees you from database-specific SQL, SmartMessage liberates your messages from transport-specific implementations. Each message knows how to validate itself, where it came from, where it's going, and what to do when it arrives. With built-in support for filtering, versioning, deduplication, and concurrent processing, SmartMessage provides enterprise-grade messaging capabilities with the simplicity Ruby developers love.

</td>
</tr>
</table>

## Table of Contents

### Getting Started
- [Quick Start](getting-started/quick-start.md)
- [Basic Usage Examples](getting-started/examples.md)

### Core Concepts
- [Architecture Overview](core-concepts/architecture.md)
- [Property System](core-concepts/properties.md)
- [Entity Addressing](core-concepts/addressing.md)
- [Message Filtering](core-concepts/message-filtering.md)
- [Message Processing](core-concepts/message-processing.md)
- [Dispatcher & Routing](core-concepts/dispatcher.md)

### Transports
- [Transport Layer](reference/transports.md)
- [Redis Queue Transport](transports/redis-queue.md) ⭐ **Featured**
- [Redis Transport Comparison](transports/redis-transport-comparison.md)
- [Redis Queue Transport](transports/redis-queue.md)

### Guides
- [Redis Queue Getting Started](guides/redis-queue-getting-started.md)
- [Advanced Routing Patterns](guides/redis-queue-patterns.md)
- [Production Deployment](guides/redis-queue-production.md)

### Reference
- [Serializers](reference/serializers.md)
- [Logging System](reference/logging.md)
- [Dead Letter Queue](reference/dead-letter-queue.md)
- [Message Deduplication](reference/message-deduplication.md)
- [Proc Handlers](reference/proc-handlers.md)

### Development
- [Troubleshooting](development/troubleshooting.md)
- [Ideas & Roadmap](development/ideas.md)

## Quick Navigation

- **New to SmartMessage?** Start with [Quick Start](getting-started/quick-start.md)
- **Need examples?** Check out [Examples](getting-started/examples.md)
- **Understanding the architecture?** Read [Architecture Overview](core-concepts/architecture.md)
- **Having issues?** Visit [Troubleshooting](development/troubleshooting.md)

## Version

This documentation is for SmartMessage v0.0.8.

For older versions, please check the git tags and corresponding documentation.
