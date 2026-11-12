# Troubleshooting

Start by turning logging on. SmartMessage logs nothing unless a logger is configured.

```ruby
SmartMessage.configure do |config|
  config.logger    = STDERR
  config.log_level = :debug
end
```

Then look at the dead letter queue, where every failure ends up:

```ruby
dlq = SmartMessage::DeadLetterQueue.default
dlq.file_path
dlq.statistics
dlq.inspect_messages(limit: 5)
```

## `TransportNotConfigured`

`SmartMessage::Errors::TransportNotConfigured: OrderMessage has no transport configured`

There is no default transport. Set one on the class (`transport ...`), on a parent class, or globally (`config.transport = ...`). See [Configuration](../core-concepts/configuration.md).

If the transport is set globally, check that `SmartMessage.configure` runs before the first `publish` or `subscribe`, and that nothing called `SmartMessage.reset_configuration!` in between.

## `ValidationError` on publish, but `new` worked

`new` does not validate; `publish` does. Inspect the message:

```ruby
message.valid?
message.validation_errors   # each has :property, :value, :message, :source
```

A `source` of `"header"` with `property: :from` means the message has no sender: set `from` on the class or pass `from:` to `new`.

## `ReservedPropertyName` when a class is loaded

A property uses a name the framework owns (`from`, `to`, `reply_to`, `uuid`, `transport`, `logger`, `to_h`, and others, or a name starting with `_sm_`). Rename the property. The full list is in [Properties and Validation](../core-concepts/properties.md).

## The handler never runs

Work through these in order.

1. **Did the program exit first?** Handlers run on a thread pool. In a short script, call `SmartMessage.shutdown` before the end.
2. **Is the class subscribed on the transport the message arrives on?** `MessageClass.transport.subscribers` shows the subscriptions. A subscription made before the transport was changed belongs to the old transport.
3. **Does the transport deliver at all?** The stdout transport calls handlers only with `loopback: true`. The memory transport with `auto_process: false` delivers only on `process_all`.
4. **Do the filters match?** A `to:` filter never matches a broadcast (`to` is `nil`); add `broadcast: true` if you want both. See [Message Filtering](../core-concepts/message-filtering.md).
5. **Was it a duplicate?** With deduplication on, a UUID that the handler has already processed is skipped. Check `SmartMessage::Stats.get('OrderMessage', 'OrderMessage.process', 'duplicate')`.
6. **Did the handler raise, or is its circuit open?** Then the message is in the dead letter queue. Check `dispatcher.circuit_breaker_stats`.
7. **Redis: was the subscriber connected when the message was published?** Redis pub/sub does not keep messages for subscribers that are not connected. Also check that publisher and subscriber use the same `namespace:`.
8. **File: is the reader starting at the end?** By default a new subscription sees only lines written after it started. Use `read_from_end: false` to read existing lines.

## The handler runs, but a property has the wrong type

The message went through JSON. A `Time` arrives as a String, a Symbol as a String, nested Hash keys as Symbols. Declare `coerce_key` for properties that need their type back. See [Serializers](../reference/serializers.md).

## Messages cross between environments or test runs on Redis

Redis pub/sub channels are global to the server. The `db` number does not separate them. Give each environment, and each test run, its own `namespace:`. See [Redis Transport](../transports/redis-transport.md).

## `TransportError` from the Redis transport

- `... is disconnected`: the transport was disconnected; call `transport.connect`.
- `Redis did not confirm the subscription to ... within 5s`: the server is unreachable or slow. Check the `url`, and raise `subscribe_timeout` if needed.

## `PublishError`, or a result that is `partial?`

Every transport (or some of them) failed. `error.result.failed` or `result.failed` lists each failed transport with its exception. The message is in the dead letter queue once per failed transport.

`BreakerMachines::CircuitOpenError` as the error means that transport's circuit is open after repeated failures. It closes again by itself after the reset time, or call `transport.reset_transport_circuits!` once the cause is fixed. See [Circuit Breakers](../reference/circuit-breakers.md).

## `UnknownMessageClass` or `MessageClassMismatch` in the log

A payload named a class that is not a loaded `SmartMessage::Base` subclass in the receiving process, or arrived on a channel that belongs to another class. The payload is in the dead letter queue. Make sure the receiving process loads the message class (for instance, requires everything under `messages/`).

## Where is the dead letter queue file?

```ruby
SmartMessage.configuration.dlq_path
```

By default `$SMART_MESSAGE_DLQ_PATH`, else `$XDG_STATE_HOME/smart_message/dead_letters.jsonl`, else `~/.local/state/smart_message/dead_letters.jsonl`. It is no longer `dead_letters.jsonl` in the working directory. See [Dead Letter Queue](../reference/dead-letter-queue.md).

## No log file appears

That is the default. Set `config.logger`; `config.logger = :default` writes to `log/smart_message.log`. See [Logging](../reference/logging.md).

## Shutdown takes several seconds

`SmartMessage.shutdown` (also run at exit) waits up to `config.shutdown_timeout` seconds (default 5) for running handlers. A handler that is blocked holds the process until the timeout, then is killed and its message dead-lettered. Lower the timeout, or fix the handler.

A Redis subscriber thread or a file poller is stopped with `transport.disconnect`, not by `SmartMessage.shutdown`.

## Handlers slow the publisher down

When the dispatcher's queue is full, the delivering thread runs handlers itself. Raise `config.dispatcher_max_threads` or `config.dispatcher_max_queue` before creating transports, or make the handlers faster. See [Dispatcher](../core-concepts/dispatcher.md).

## Looking at what is going on

```ruby
transport  = OrderMessage.transport
dispatcher = transport.dispatcher

transport.connected?
transport.subscribers
transport.transport_circuit_stats
dispatcher.status
dispatcher.circuit_breaker_stats
OrderMessage.ddq_stats
SmartMessage::Stats.stat
```

## Reporting a problem

Open an issue at <https://github.com/MadBomber/smart_message/issues> with the SmartMessage version (`SmartMessage::VERSION`), the Ruby version, the transport and its options, and the smallest program that shows the problem.
