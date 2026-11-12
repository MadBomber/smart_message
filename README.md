> [!CAUTION]
> SmartMessage is under active alpha-level development. Version 0.1.0 changes the public API in several places; see [Upgrading from 0.0.x](docs/getting-started/upgrading.md) and the [CHANGELOG.md](CHANGELOG.md).
<br/><br/>

<table border="0">
<tr>
<td width="30%" valign="top">

<img src="docs/assets/images/smart_message.jpg" alt="SmartMessage Logo" />
<br/>
See <a href="https://madbomber.github.io/smart_message/">Documentation Website</a>
</td>
<td width="70%" valign="top">

# SmartMessage

SmartMessage is a Ruby messaging framework that separates a message from the transport that carries it. A message class declares its properties, validations, addressing and handlers; a transport moves the serialized message. The same message class works over an in-process transport in a test and over Redis pub/sub in production.

The comparison the project uses is ActiveRecord: ActiveRecord keeps a model independent of the database behind it, SmartMessage keeps a message independent of the transport behind it.

</td>
</tr>
</table>

## Requirements

- Ruby 4.0 or newer
- A Redis server, only if you use the Redis transport or the Redis deduplication backend

## Installation

```ruby
gem 'smart_message'
```

Then run `bundle install`, or install it directly with `gem install smart_message`.

## Quick Start

This is a complete program. Save it and run it with `ruby`.

```ruby
require 'smart_message'

# In an application this class lives in messages/order_message.rb
class OrderMessage < SmartMessage::Base
  description 'A customer order'
  from 'order-service'
  transport SmartMessage::Transport::MemoryTransport.new

  property :order_id, required: true
  property :amount,   required: true,
                      validate: ->(value) { value.positive? },
                      validation_message: 'amount must be positive'
  property :currency, default: 'USD', validate: %w[USD EUR GBP]

  # The default handler is a class method
  def self.process(message)
    puts "Order #{message.order_id}: #{message.amount} #{message.currency} from #{message.from}"
  end
end

OrderMessage.subscribe

result = OrderMessage.new(order_id: 'ORD-1', amount: 99.99).publish
puts "published: #{result.success?}"

# Handlers run on a thread pool.  Wait for them before the script ends.
SmartMessage.shutdown
```

Output:

```
published: true
Order ORD-1: 99.99 USD from order-service
```

The two lines can appear in either order, because the handler runs on another thread. The [Quick Start guide](docs/getting-started/quick-start.md) continues from here.

## What It Provides

- Message classes with declared properties, defaults, validation, descriptions and a schema version
- `from` / `to` / `reply_to` addressing, and subscription filters on those fields
- Four transports: memory, stdout, file, and Redis pub/sub
- Publishing to several transports at once, with a per-transport result
- Handlers as class methods, blocks, procs or lambdas, run on a bounded thread pool
- A file-based dead letter queue that captures every failure and can replay it
- Per-handler deduplication with a memory or Redis backend
- Circuit breakers around each transport and each handler
- JSON serialization
- Optional logging through any Ruby logger

## Transports and Delivery Semantics

There is no default transport. Set one on the message class, or globally with `SmartMessage.configure`. Publishing or subscribing without one raises `SmartMessage::Errors::TransportNotConfigured`.

| Transport | Create with | What it does |
|-----------|-------------|--------------|
| Memory | `SmartMessage::Transport.create(:memory)` | In-process only. Delivers to subscribers in the same process. For tests and local development. |
| Stdout | `SmartMessage::Transport.create(:stdout)` | Writes one JSON line per message to an IO. Write-only unless `loopback: true`. |
| File | `SmartMessage::Transport.create(:file, file_path: 'messages.jsonl')` | Appends one JSON line per message. Subscribers tail the file. |
| Redis | `SmartMessage::Transport.create(:redis, namespace: 'staging')` | Redis pub/sub. At-most-once: a subscriber that is not connected when a message is published never sees it. |

Redis pub/sub channels are global to a Redis server. The `db` number does not separate them, so use `namespace:` to keep environments or test runs apart.

Details: [Transports](docs/reference/transports.md), [Memory](docs/transports/memory-transport.md), [Stdout](docs/transports/stdout-transport.md), [File](docs/transports/file-transport.md), [Redis](docs/transports/redis-transport.md).

Transports for NATS, RabbitMQ, named pipes and lanet exist as separate `smart_message-transport-*` gems; they have not yet been updated for 0.1.0.

## Publishing

`publish` validates the message, sends it on every configured transport, and returns a `SmartMessage::PublishResult`.

```ruby
result = message.publish

result.success?   # every transport accepted the message
result.partial?   # some did, some did not
result.failed.each { |outcome| warn "#{outcome.transport_name}: #{outcome.error.message}" }
```

When every transport fails, `publish` raises `SmartMessage::Errors::PublishError`; the result is on `error.result`. A message that a transport could not publish is written to the dead letter queue. See [Publishing](docs/reference/publishing.md).

## Validation

`new` does not validate. `valid?`, `validation_errors` and `validate!` do, and `publish` calls `validate!`.

```ruby
message = OrderMessage.new(amount: -5)   # no error here
message.valid?                           # => false

begin
  message.publish
rescue SmartMessage::Errors::ValidationError => e
  e.errors   # => [{ property: :order_id, ... }, { property: :amount, ... }]
end
```

Some property names are reserved (`from`, `to`, `reply_to`, `uuid`, `publish`, `transport`, and others, plus anything starting with `_sm_`). Declaring one raises `SmartMessage::Errors::ReservedPropertyName` when the class is defined. See [Properties and Validation](docs/core-concepts/properties.md).

## Configuration

Settings are looked up in this order: the message instance, then its class (and the class's parents), then the global configuration.

```ruby
SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport.create(:redis, namespace: 'production')
  config.logger    = 'log/smart_message.log'   # logging is off unless this is set
  config.dlq_path  = '/var/lib/my_app/dead_letters.jsonl'
end
```

See [Configuration](docs/core-concepts/configuration.md) and [Logging](docs/reference/logging.md).

## Reliability

- **Dead letter queue.** A failed publish, a payload that cannot be decoded, a handler that raises, a call rejected by an open circuit, and a handler killed at shutdown each put the message in a JSON Lines file. The default path is `$SMART_MESSAGE_DLQ_PATH`, else `$XDG_STATE_HOME/smart_message/dead_letters.jsonl` (`~/.local/state/smart_message/dead_letters.jsonl`). See [Dead Letter Queue](docs/reference/dead-letter-queue.md).
- **Deduplication.** With `enable_deduplication!` on a message class, each handler keeps its own record of message UUIDs. A UUID is reserved before the handler runs and released if the handler fails. See [Message Deduplication](docs/reference/message-deduplication.md).
- **Circuit breakers.** One per transport instance for publishing, one per handler per message class for processing. See [Circuit Breakers](docs/reference/circuit-breakers.md).
- **Dispatcher.** Handlers run on a bounded thread pool; each handler receives its own copy of the message. `SmartMessage.shutdown(timeout:)` waits for running handlers. See [Dispatcher](docs/core-concepts/dispatcher.md).

## Serialization

JSON is the only serializer shipped. A JSON round trip changes some Ruby types: `Time` and `Date` arrive as ISO 8601 strings, Symbols as Strings, `BigDecimal` as a String, and Hash keys as Symbols. Declare `coerce_key` on the message class to get a type back. See [Serializers](docs/reference/serializers.md).

## Examples

Runnable examples are grouped by transport: [examples/memory/](examples/memory/), [examples/file/](examples/file/), [examples/redis/](examples/redis/), and a multi-process demo in [examples/city_scenario/](examples/city_scenario/).

## Documentation

- [Quick Start](docs/getting-started/quick-start.md)
- [Upgrading from 0.0.x](docs/getting-started/upgrading.md)
- [Architecture](docs/core-concepts/architecture.md)
- [Full documentation index](docs/index.md), also published at <https://madbomber.github.io/smart_message/>

## Development

After checking out the repo, run:

```bash
bin/setup      # Install dependencies
bin/console    # Start interactive console
rake test      # Run test suite
```

```bash
ruby -Ilib:test test/base_test.rb  # Run specific test file
```

Tests that need Redis expect a server on `localhost:6379` and skip themselves when there is none.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MadBomber/smart_message.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
