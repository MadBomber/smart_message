# Transports

A transport moves serialized messages. SmartMessage ships four:

| Name | Class | Page |
|------|-------|------|
| `:memory` | `SmartMessage::Transport::MemoryTransport` | [Memory Transport](../transports/memory-transport.md) |
| `:stdout` | `SmartMessage::Transport::StdoutTransport` | [Stdout Transport](../transports/stdout-transport.md) |
| `:file` | `SmartMessage::Transport::FileTransport` | [File Transport](../transports/file-transport.md) |
| `:redis` | `SmartMessage::Transport::RedisTransport` | [Redis Transport](../transports/redis-transport.md) |

Transports for NATS, RabbitMQ, named pipes and lanet exist as separate `smart_message-transport-*` gems; they have not yet been updated for 0.1.0.

## Delivery semantics

The transports do not offer the same guarantees. Know which one you are using.

| | Memory | Stdout | File | Redis |
|---|--------|--------|------|-------|
| Reaches | subscribers on the same transport instance, in the same process | an IO (default `$stdout`) | every process tailing the same file | every process subscribed on the same Redis server and namespace, at that moment |
| Crosses processes | no | only as text on the IO | yes | yes |
| Subscribing | yes | only with `loopback: true`, and only this instance's own messages | yes, by polling the file | yes |
| Stored | optionally, in memory, up to `max_messages` | no | yes: the file is the store, and it only grows | no |
| A subscriber that starts later | sees nothing earlier | not applicable | sees only new lines, unless `read_from_end: false` | sees nothing earlier |
| A subscriber that is down | not applicable | not applicable | catches up only if it re-reads the file from the start | **misses the message** |
| Guarantee | in-process hand-off | write-only | durable append; each reader delivers each line once per pass over the file | at most once |

In words:

- **Memory** is in-process. `publish` hands the message to the handlers subscribed on that transport instance in the same process. Nothing leaves the process. Use it for tests and local development.
- **Stdout** is write-only. It prints one JSON line per message to an IO. Handlers are called only when the transport was created with `loopback: true`, and then only for messages published through that same instance.
- **File** is append-only JSON Lines. Writers append; readers tail the file with a poller. The file is never trimmed by the transport.
- **Redis** is Redis pub/sub, which is at-most-once. Redis does not store published messages: a message reaches the subscribers connected at the moment it is published and nobody else. A process that is down, not yet subscribed, or reconnecting misses it. Pub/sub channels are global to the Redis server, so the `db` number does not isolate environments; use `namespace:`.

None of the shipped transports provides queueing with acknowledgement, consumer groups, or routing by pattern. If every message must reach a consumer that may be down, pub/sub is the wrong tool; the file transport, or a transport backed by a durable broker, is closer to what you need.

Whatever the transport, a failure on the way is captured: a publish that fails, a payload that cannot be decoded, and a handler that fails all put the message in the [dead letter queue](dead-letter-queue.md).

## Choosing

| You want | Use |
|----------|-----|
| Unit tests, examples, one process | Memory |
| To see messages while developing, or pipe them to another program | Stdout |
| An audit trail, or simple hand-off between processes on one machine | File |
| Live fan-out between processes or machines, where a missed message is acceptable | Redis |
| Live delivery plus a record of everything published | Redis and File together (see [Publishing](publishing.md)) |

## Creating a transport

Directly, or by registered name:

```ruby
SmartMessage::Transport::MemoryTransport.new(auto_process: false)

SmartMessage::Transport.create(:memory, auto_process: false)
SmartMessage::Transport.create(:stdout)
SmartMessage::Transport.create(:file, file_path: 'log/messages.jsonl')
SmartMessage::Transport.create(:redis, url: 'redis://localhost:6379', namespace: 'staging')

SmartMessage::Transport.available     # => [:memory, :stdout, :file, :redis]
SmartMessage::Transport.create(:nope) # raises ArgumentError
```

There is no default transport. Assign one to a message class or to the global configuration; see [Configuration](../core-concepts/configuration.md).

## Options common to every transport

| Option | Meaning |
|--------|---------|
| `serializer:` | A serializer instance. Default `SmartMessage::Serializer::Json.new`. |
| `dispatcher:` | A `SmartMessage::Dispatcher` to share. Default: a new one for this transport. |
| `circuit_breaker:` | `{ transport_publish: {...}, message_processor: {...} }` overrides; see [Circuit Breakers](circuit-breakers.md). |

## The transport interface

| Method | Meaning |
|--------|---------|
| `publish(message)` | Encode and send, inside the transport's circuit breaker. Returns `true` or raises. Application code normally calls `message.publish` instead. |
| `subscribe(message_class, handler_id, filters)` | Called by `MessageClass.subscribe` |
| `unsubscribe(message_class, handler_id)`, `unsubscribe!(message_class)` | Called by `MessageClass.unsubscribe` / `unsubscribe!` |
| `subscribers` | Current subscriptions, by message class name |
| `connected?`, `connect`, `disconnect` | Connection state. `disconnect` is safe to call more than once and never closes an IO the transport was handed. |
| `transport_circuit_stats`, `reset_transport_circuits!` | The publish circuit breaker |
| `encode_message(message)`, `decode_message(payload)` | The envelope codec with this transport's serializer |
| `dispatcher`, `serializer`, `options` | Readers |

## Writing a transport

Subclass `SmartMessage::Transport::Base` and implement `do_publish(message_class, serialized_message)`. Raise on failure; never return a failure value. Hand inbound payloads to `receive(message_class, payload)`; pass `nil` for the class when your medium has no channels.

You may also override `configure` (called from `initialize`), `default_options`, `default_serializer`, `subscribe` / `unsubscribe` / `unsubscribe!` (call `super`, then start or stop listening), `connected?`, `connect` and `disconnect`.

This complete program defines a transport that keeps payloads in an Array and delivers them when asked:

```ruby
require 'smart_message'

class ArrayTransport < SmartMessage::Transport::Base
  attr_reader :payloads

  def default_options
    { limit: 100 }
  end

  def configure
    @payloads = []
    @lock     = Mutex.new
  end

  def do_publish(message_class, serialized_message)
    @lock.synchronize do
      raise SmartMessage::Errors::TransportError, 'ArrayTransport is full' if @payloads.size >= @options[:limit]

      @payloads << [message_class, serialized_message]
    end
  end

  # Deliver everything stored so far to this transport's subscribers.
  def flush
    pending = @lock.synchronize { @payloads.shift(@payloads.size) }
    pending.each { |message_class, payload| receive(message_class, payload) }
    pending.size
  end
end

SmartMessage::Transport.register(:array, ArrayTransport)

# messages/note_message.rb
class NoteMessage < SmartMessage::Base
  from 'notes'
  transport SmartMessage::Transport.create(:array, limit: 10)
  property :text, required: true

  def self.process(message)
    puts "note: #{message.text}"
  end
end

NoteMessage.subscribe
NoteMessage.new(text: 'first').publish
NoteMessage.new(text: 'second').publish

puts "stored: #{NoteMessage.transport.payloads.size}"
puts "delivered: #{NoteMessage.transport.flush}"

SmartMessage.shutdown
```

`register` raises `ArgumentError` unless the class inherits from `SmartMessage::Transport::Base`.
