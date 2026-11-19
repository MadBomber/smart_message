# Upgrading from 0.0.x

SmartMessage 0.1.0 is a reliability release that changes the public API in several places. This page walks through each breaking change in the [CHANGELOG](https://github.com/MadBomber/smart_message/blob/main/CHANGELOG.md), with the code you had and the code you need.

A quick checklist:

1. Run on Ruby 4.0 or newer.
2. Give every message class a transport.
3. Stop using the return value of `publish` as a number.
4. Move validation rescues from `new` to `publish` / `validate!`.
5. Rename any property that uses a reserved name.
6. Configure a logger if you relied on the default log file.
7. Decide where the dead letter queue file should live.
8. Replace removed file transport and stdout transport options.
9. Replace `db:` isolation of Redis environments with `namespace:`.

## Ruby 4.0

The gem now requires Ruby 4.0 or newer (`required_ruby_version = '>= 4.0'`).

## No default transport

Before, a message class with no transport fell back to a Redis connection on `localhost`. Now there is no fallback.

```ruby
# Before: published to Redis on localhost without being told to
class OrderMessage < SmartMessage::Base
  property :order_id
end
OrderMessage.new(order_id: 1, from: 'orders').publish

# After: say which transport
class OrderMessage < SmartMessage::Base
  transport SmartMessage::Transport.create(:redis, namespace: 'production')
  property :order_id
end

# or once, for every class without its own
SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport.create(:redis, namespace: 'production')
end
```

Publishing or subscribing without a transport raises `SmartMessage::Errors::TransportNotConfigured`.

## `publish` returns a `PublishResult`

Before, `publish` returned a running count of published messages, and a transport that failed could still be counted as a success. Now it returns a `SmartMessage::PublishResult` with one outcome per transport.

```ruby
# Before
count = message.publish

# After
result = message.publish
result.success?     # every transport accepted it
result.partial?     # some accepted it, some failed
result.failure?     # none accepted it (publish raises in this case)
result.successful   # Array of outcomes
result.failed       # Array of outcomes; outcome.error is the exception
result.errors       # the exceptions
result.outcomes     # every outcome
```

When every transport fails, `publish` raises `SmartMessage::Errors::PublishError`, and the result is on `error.result`:

```ruby
begin
  message.publish
rescue SmartMessage::Errors::PublishError => e
  e.result.failed.each { |outcome| warn "#{outcome.transport_name}: #{outcome.error.message}" }
end
```

`Transport#publish` (the method on a transport instance) now raises the transport's own error. It used to return a fallback Hash when its circuit breaker tripped.

If you need the count, read it from `SmartMessage::Stats.get('OrderMessage', 'publish')`.

See [Publishing](../reference/publishing.md).

## Validation happens in one place

Before, `new` raised for a missing required property or a missing `from`. Now `new` never validates.

```ruby
# Before
OrderMessage.new(amount: 5)            # raised: order_id is required

# After
message = OrderMessage.new(amount: 5)  # no error
message.valid?                         # => false
message.validation_errors              # => [{ property: :order_id, value: nil, message: "...", source: "message" }]

begin
  message.publish                      # publish calls validate!
rescue SmartMessage::Errors::ValidationError => e
  e.errors                             # the same Array that validation_errors returns
end
```

Code that built a message and assumed it was valid because `new` returned should call `valid?` or `validate!`.

See [Properties and Validation](../core-concepts/properties.md).

## Reserved property names

Declaring a property with one of these names raises `SmartMessage::Errors::ReservedPropertyName` when the class is defined:

`from`, `to`, `reply_to`, `uuid`, `publish`, `transport`, `transports`, `config`, `logger`, `validate!`, `valid?`, `validation_errors`, `to_h`, `to_hash`, `message_header`, and anything starting with `_sm_`.

```ruby
# Before: accepted, and collided with the framework at run time
class TransferMessage < SmartMessage::Base
  property :from
  property :to
end

# After: choose names that say what the values are
class TransferMessage < SmartMessage::Base
  property :source_account
  property :target_account
end
```

## Message hashes

Nested Hashes keep the keys they were given. Before, they were converted to indifferent-access hashes; now only the top level of a message accepts both Strings and Symbols.

```ruby
message = OrderMessage.new(order_id: 1, customer: { 'name' => 'Ann' })

# Before
message.customer[:name]     # => "Ann"

# After
message.customer['name']    # => "Ann"
message.customer[:name]     # => nil
```

After a JSON round trip (that is, in a handler), nested keys are Symbols. See [Serializers](../reference/serializers.md).

`to_h` returns the header as a plain Hash under `:_sm_header`, not a `SmartMessage::Header` object:

```ruby
message.to_h[:_sm_header]          # => { uuid: "...", message_class: "OrderMessage", ... }
message.to_h[:_sm_header][:uuid]   # After
message._sm_header.uuid            # the Header object is still here
```

## Class settings are inherited the same way everywhere

Transport, logger, version, addressing, deduplication settings, validators and property descriptions are read from the class, else from its parent. A subclass can no longer change its parent or a sibling.

```ruby
class BaseEvent < SmartMessage::Base
  from 'events'
  transport SmartMessage::Transport.create(:memory)
end

class UserEvent < BaseEvent
  from 'user-service'    # changes UserEvent only
end

BaseEvent.from   # => "events"   (before: could become "user-service")
UserEvent.transport.equal?(BaseEvent.transport)   # => true, inherited
```

`description` is the exception: it is not inherited. A subclass without its own description gets the default `"<ClassName> is a SmartMessage"`.

## Logging is off unless configured

Before, SmartMessage created `log/smart_message.log` and wrote to it by default. Now nothing is logged and no directory is created unless you configure a logger.

```ruby
# To get the 0.0.x behaviour back
SmartMessage.configure do |config|
  config.logger = :default   # Lumberjack logger writing to log/smart_message.log
end
```

The three shipped loggers (`Lumberjack`, `Default`, `Null`) now share one interface, `SmartMessage::Logger::Base`. In the Lumberjack JSON format, keyword data given to a log call is nested under `"data"`:

```ruby
logger.info('Order placed', order_id: 42)
# Before: order_id was a top-level field of the JSON line
# After:  {"timestamp":"...","level":"INFO","message":"Order placed","source":"...","data":{"order_id":42}}
```

See [Logging](../reference/logging.md).

## Dead letter queue location

Before, the default dead letter queue was `dead_letters.jsonl` in the current working directory. Now it is, in order:

1. `$SMART_MESSAGE_DLQ_PATH`, when set
2. `$XDG_STATE_HOME/smart_message/dead_letters.jsonl`, when `XDG_STATE_HOME` is set
3. `~/.local/state/smart_message/dead_letters.jsonl`

```ruby
# To choose the file
SmartMessage.configure do |config|
  config.dlq_path = '/var/lib/my_app/dead_letters.jsonl'
end
```

If you have an old `dead_letters.jsonl` with entries you still need, point `config.dlq_path` at it or create a queue for it with `SmartMessage::DeadLetterQueue.new('dead_letters.jsonl')` and replay from there.

See [Dead Letter Queue](../reference/dead-letter-queue.md).

## Deduplication API

Deduplication queues now belong to the dispatcher: one per handler per message class. The dispatcher reserves a UUID before the handler runs and releases it if the handler fails, so you no longer mark messages yourself.

```ruby
# Before
def self.process(message)
  return if message.duplicate?
  handle(message)
  message.mark_as_processed!
end

# After: the dispatcher has already done it
def self.process(message)
  handle(message)
end
```

Removed: `message.duplicate?`, `message.mark_as_processed!`, `MessageClass.duplicate_uuid?`, `MessageClass.get_ddq_instance`.

`ddq_stats` has a new shape:

```ruby
OrderMessage.ddq_stats
# Before: one flat Hash for the class
# After:
# {
#   enabled: true,
#   queues: {
#     "OrderMessage:OrderMessage.process" => { size: 100, storage_type: :memory, current_count: 3, ... }
#   }
# }
```

The Redis backend stores one key per UUID with a TTL instead of a list and a set. `ddq_size` no longer bounds Redis storage; use the `ttl:` option:

```ruby
ddq_storage :redis, ttl: 3600   # seconds; 3600 is the default
```

Custom backends must implement atomic `reserve(uuid)` and `release(uuid)`.

See [Message Deduplication](../reference/message-deduplication.md).

## Circuit breakers

- There is one circuit per transport instance and one per handler per message class. A failing handler no longer opens the circuit for other handlers.
- Each circuit keeps its state in memory. The `storage: :redis` option is gone.
- `SmartMessage::CircuitBreaker::Fallbacks` procs take the error only.
- Serializers are no longer wrapped in a circuit. A failed encode raises `SmartMessage::Errors::SerializationError`; a failed decode raises `SmartMessage::Errors::DecodeError`.

```ruby
# Before
SmartMessage::CircuitBreaker::Fallbacks.dead_letter_queue        # proc { |exception, *args| ... }

# After: the message comes from a block evaluated on the circuit's owner
SmartMessage::CircuitBreaker::Fallbacks.dead_letter_queue { current_message }   # proc { |exception| ... }
```

For retries, use the new `SmartMessage::CircuitBreaker.with_retries` loop. See [Circuit Breakers](../reference/circuit-breakers.md).

## File transport

The file transport is now an append-only JSON Lines writer with a tailing poller. Named pipe support, the asynchronous publish queue, file rotation and partitioned files are removed, along with their options (`file_type`, `async`, `rotate_size`, `directory`, `subscription_mode`, and the rest). `file_path:` is required.

```ruby
# Before
SmartMessage::Transport::FileTransport.new(
  file_path: 'messages.log', file_format: :lines, async: true, rotate_size: 10_000_000
)

# After: the only options
SmartMessage::Transport::FileTransport.new(
  file_path:          'messages.jsonl',   # required
  create_directories: true,
  encoding:           nil,
  poll_interval:      0.5,
  read_from_end:      true
)
```

If you need rotation, rotate the file with an external tool; a reader starts again from the beginning when the file becomes shorter than what it has consumed. See [File Transport](../transports/file-transport.md).

## Stdout transport

`StdoutTransport` no longer inherits from the file transport. Its options are `output:` (an IO) and `loopback:`. It never closes the IO; before, `disconnect` closed `$stdout`.

```ruby
# Before
SmartMessage::Transport::StdoutTransport.new(file_path: 'messages.log')

# After
SmartMessage::Transport::StdoutTransport.new                    # writes to $stdout
SmartMessage::Transport::StdoutTransport.new(output: $stderr)
SmartMessage::Transport::FileTransport.new(file_path: 'messages.jsonl')   # to write to a file
```

See [Stdout Transport](../transports/stdout-transport.md).

## Memory transport

- Stored entries are `{ message_class:, payload:, published_at: }`. The `payload` is the serialized String (before: a `message:` key holding the message object).
- Messages are stored only when `auto_process: false`, or when you pass `store_messages: true`. Before, every message was stored.
- `process_all` removes what it delivers, so calling it twice does not deliver twice.
- Messages are serialized and decoded on delivery, as a real transport does. Handlers therefore see JSON type changes (a `Time` property arrives as a String). Pass `serialize: false` to hand handlers copies of the published object instead.

```ruby
# Before
transport = SmartMessage::Transport::MemoryTransport.new
message.publish
transport.all_messages.first[:message].order_id

# After
transport = SmartMessage::Transport::MemoryTransport.new(store_messages: true)
message.publish
entry = transport.all_messages.first
transport.decode_message(entry[:payload]).order_id
```

See [Memory Transport](../transports/memory-transport.md).

## Redis transport

- Publishing or subscribing after `disconnect` raises `SmartMessage::Errors::TransportError` until you call `connect`.
- `subscribe` returns once Redis has confirmed the subscription, or raises `TransportError` after `subscribe_timeout` seconds (default 5).
- New `namespace:` option. Redis pub/sub channels are global to the server; the `db` number never separated them.

```ruby
# Before: did not isolate anything for pub/sub
SmartMessage::Transport::RedisTransport.new(url: 'redis://localhost:6379', db: 15)

# After
SmartMessage::Transport::RedisTransport.new(url: 'redis://localhost:6379', namespace: 'test')
```

See [Redis Transport](../transports/redis-transport.md).

## `Transport.create`

```ruby
# Before
SmartMessage::Transport.create(:nope)   # => nil

# After
SmartMessage::Transport.create(:nope)   # raises ArgumentError: Unknown transport: :nope. Available: [:memory, :stdout, :file, :redis]
```

## Removed

| Removed | Use instead |
|---------|-------------|
| `SimpleStats` | `SmartMessage::Stats` (`add`, `get`, `reset`, `stat`) |
| `SmartMessage::Base.decode` | `transport.decode_message(payload)` or `SmartMessage::Envelope.decode(payload, serializer:)` |
| `SmartMessage::Errors::SerializerNotConfigured` | Not raised any more; a transport always has a serializer |
| The `_version` accessor | `MessageClass.version`, `message._sm_header.version` |
| Dependencies on `activesupport`, `async`, `async-redis`, `colorize` | Add them to your own Gemfile if your code used them through SmartMessage |

## `MessageClass.header` takes a block only

```ruby
# Still works
class OrderMessage < SmartMessage::Base
  header do
    from 'order-service'
    to   'fulfillment'
  end
end

# Raises ArgumentError
OrderMessage.header          # no block
OrderMessage.header(:from)   # arguments
```

To read a message's header, use `message._sm_header` (or `message.message_header`).

## Extension transport gems

The separate `smart_message-transport-*` gems (NATS, RabbitMQ, named pipes, lanet) have not yet been updated for 0.1.0.
