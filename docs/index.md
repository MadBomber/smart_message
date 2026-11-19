# SmartMessage Documentation

<table border="0">
<tr>
<td width="30%" valign="top">
  <img src="assets/images/smart_message.jpg" alt="SmartMessage Logo" width="200" />
</td>
<td width="70%" valign="top">

SmartMessage is a Ruby messaging framework that separates a message from the transport that carries it. A message class declares its properties, validations, addressing and handlers; a transport moves the serialized message.
<br/><br/>
The comparison the project uses is ActiveRecord: ActiveRecord keeps a model independent of the database behind it, SmartMessage keeps a message independent of the transport behind it.

</td>
</tr>
</table>

This documentation describes SmartMessage 0.1.0, which requires Ruby 4.0 or newer. If you are coming from an earlier version, read [Upgrading from 0.0.x](getting-started/upgrading.md) first.

## Getting Started

- [Quick Start](getting-started/quick-start.md): a complete program, then each piece in turn
- [Examples](getting-started/examples.md): where the runnable example programs are
- [Upgrading from 0.0.x](getting-started/upgrading.md): every breaking change with before and after

## Core Concepts

- [Architecture](core-concepts/architecture.md): how a message travels from `publish` to a handler
- [Properties and Validation](core-concepts/properties.md): declaring properties, validation, reserved names, versions
- [Addressing](core-concepts/addressing.md): `from`, `to` and `reply_to`
- [Message Filtering](core-concepts/message-filtering.md): subscribing to a subset of messages
- [Handlers](core-concepts/message-processing.md): class methods, blocks, procs and lambdas
- [Dispatcher](core-concepts/dispatcher.md): the thread pool, message copies, shutdown
- [Configuration](core-concepts/configuration.md): setting precedence and the global configuration

## Transports

- [Transports](reference/transports.md): delivery semantics of each transport, choosing one, writing your own
- [Memory Transport](transports/memory-transport.md)
- [Stdout Transport](transports/stdout-transport.md)
- [File Transport](transports/file-transport.md)
- [Redis Transport](transports/redis-transport.md)

## Reference

- [Publishing](reference/publishing.md): `PublishResult`, `PublishError`, several transports at once
- [Serializers](reference/serializers.md): JSON, type changes on a round trip, `coerce_key`
- [Logging](reference/logging.md)
- [Dead Letter Queue](reference/dead-letter-queue.md)
- [Message Deduplication](reference/message-deduplication.md)
- [Circuit Breakers](reference/circuit-breakers.md)

## Development

- [Troubleshooting](development/troubleshooting.md)
- [Ideas](development/ideas.md): possible future directions, none of them implemented
