# Redis Transport

`SmartMessage::Transport::RedisTransport` uses Redis pub/sub. Each message class is one Redis channel, named after the class and prefixed with the namespace when one is set.

## Delivery semantics: at most once

Redis pub/sub does not store messages.

- A message reaches the subscribers that are **connected at the moment it is published**, and nobody else.
- A process that is down, has not subscribed yet, or is reconnecting **misses the message**. There is no replay and no backlog.
- Every connected subscriber of a channel gets every message (fan-out). There is no load balancing between subscribers and no acknowledgement.
- Publishing to a channel with no subscribers succeeds; the message is discarded by Redis.

Use this transport when a missed message is acceptable, or pair it with something durable. If every message must arrive, pub/sub is the wrong mechanism.

## Namespaces, not database numbers

Redis pub/sub channels are **global to the Redis server**. The `db` number selects a keyspace for commands such as `GET` and `SET`; it does not separate pub/sub channels. Two environments, or two test runs, that share one server see each other's messages even when they use different `db` numbers.

Use `namespace:` to keep them apart. It prefixes every channel:

```ruby
staging = SmartMessage::Transport::RedisTransport.new(namespace: 'staging')
staging.channel_for('OrderMessage')   # => "staging:OrderMessage"

plain = SmartMessage::Transport::RedisTransport.new
plain.channel_for('OrderMessage')     # => "OrderMessage"
```

For tests, use a namespace that is unique to the run:

```ruby
require 'securerandom'

transport = SmartMessage::Transport::RedisTransport.new(namespace: "test-#{SecureRandom.hex(4)}")
```

## Options

```ruby
SmartMessage::Transport::RedisTransport.new(
  url:                'redis://localhost:6379',
  db:                 0,
  namespace:          nil,
  reconnect_attempts: 5,
  reconnect_delay:    1,
  subscribe_timeout:  5
)

SmartMessage::Transport.create(:redis, url: ENV.fetch('REDIS_URL'), namespace: 'production')
```

| Option | Default | Meaning |
|--------|---------|---------|
| `url` | `redis://localhost:6379` | Redis URL |
| `db` | `0` | Database number, used for commands only. It does not isolate pub/sub. |
| `namespace` | `nil` | Channel prefix: `"namespace:ClassName"` |
| `reconnect_attempts` | `5` | Retries for a lost connection |
| `reconnect_delay` | `1` | Seconds between subscriber reconnects |
| `subscribe_timeout` | `5` | Seconds to wait for Redis to confirm a subscription |

## Connections

The transport uses two connections. One publishes. A second, long-lived connection subscribes; it is opened by the first `subscribe` and then gains and loses channels with `SUBSCRIBE` and `UNSUBSCRIBE`, so changing the set of subscriptions does not drop messages on the channels already subscribed.

`subscribe` returns once Redis has confirmed the subscription. If Redis does not confirm within `subscribe_timeout` seconds it raises `SmartMessage::Errors::TransportError`. A message published after `subscribe` returns is therefore seen by that subscriber.

When the subscriber connection is lost, the transport logs it, waits `reconnect_delay` seconds and reconnects, resubscribing every channel, up to `reconnect_attempts` times. Messages published while it was disconnected are missed. After the last attempt the subscriber stops and the failure is logged; configure a [logger](../reference/logging.md) so that you can see it.

```ruby
transport.connected?            # => true when the publishing connection answers PING
transport.subscribed_channels   # => ["staging:OrderMessage"]  channels Redis has confirmed
transport.disconnect            # stop the subscriber and close both connections
transport.connect               # reopen, and resubscribe channels that still have handlers
```

After `disconnect`, publishing or subscribing raises `SmartMessage::Errors::TransportError` until `connect` is called. `disconnect` is safe to call more than once.

## What is checked on receive

A payload that arrives on a channel is decoded, and the class named in its header must match the channel it arrived on. A mismatch, an unknown class or a payload that is not a SmartMessage envelope is logged and stored in the [dead letter queue](../reference/dead-letter-queue.md); the subscription stays alive.

## A complete program

This needs a Redis server on `localhost:6379`.

```ruby
require 'smart_message'
require 'securerandom'

transport = SmartMessage::Transport::RedisTransport.new(
  url:       ENV.fetch('REDIS_URL', 'redis://localhost:6379'),
  namespace: "example-#{SecureRandom.hex(4)}"
)

# messages/sensor_reading.rb
class SensorReading < SmartMessage::Base
  from 'sensor-7'
  property :celsius, required: true

  def self.process(message)
    puts "reading from #{message.from}: #{message.celsius} C"
  end
end

SensorReading.transport(transport)
SensorReading.subscribe                 # returns once Redis has confirmed

puts "channel: #{transport.subscribed_channels.first}"

SensorReading.new(celsius: 21.5).publish
SensorReading.new(celsius: 22.0).publish

sleep 0.5                               # the messages travel through Redis
transport.disconnect
SmartMessage.shutdown
```

In a real system the publisher and the subscriber are different processes that use the same `url` and `namespace`. Start the subscriber first: a reading published before it subscribes is gone.

## Deduplication across processes

The Redis [deduplication backend](../reference/message-deduplication.md) is independent of this transport. It lets several processes share one record of handled UUIDs, whichever transport delivered the message.
