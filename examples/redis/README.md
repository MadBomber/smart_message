# Redis Transport Examples

Examples that use `SmartMessage::Transport::RedisTransport`, the Redis pub/sub transport.

## What the Redis transport is

- Each message class is one Redis channel, named after the class. With the `namespace:` option the channel is `"namespace:ClassName"`.
- Every subscriber that is connected when a message is published receives it. Redis pub/sub is a fan-out: it does not balance load between subscribers.
- Delivery is **at most once**. Redis pub/sub does not store messages, so a process that is down, not yet subscribed, or reconnecting misses what was published meanwhile. Use a durable transport when every message must arrive.
- Pub/sub channels are global to a Redis server. The `db` number does **not** separate them. Two environments (or two test runs) on one server see each other's messages unless they use different namespaces.

## Prerequisites

A Redis server. The examples connect to `redis://localhost:6379` unless `SMART_MESSAGE_TEST_REDIS_URL` says otherwise.

```bash
brew install redis && brew services start redis    # macOS
sudo apt install redis-server                      # Debian/Ubuntu
```

## Running

From the repository root:

```bash
bundle exec ruby -Ilib examples/redis/01_smart_home_iot_demo.rb
```

Each numbered script finishes on its own in a few seconds, checks the outcomes it demonstrates, and exits non-zero with a list of the failed checks when one is wrong. It also exits non-zero when no Redis server answers.

A run uses its own Redis namespace (`sm_example_<random>`) and its own temporary directory for the log file and the dead letter queue. Both are gone when the script ends; nothing is written into the repository.

## Files

| File | Purpose |
|------|---------|
| `01_smart_home_iot_demo.rb` | Three devices, a dashboard and an app exchange four message types |
| `messages/*.rb` | The message classes, one per file |
| `support.rb` | Shared setup: namespace, temporary directory, `wait_until`, `check`, cleanup |
| `smart_home_iot_dataflow.md` | The message flows of the smart home example, with diagrams |

## 01_smart_home_iot_demo.rb

| Message | Publisher | Subscriber | Routing |
|---------|-----------|------------|---------|
| `SensorDataMessage` | devices | dashboard | every message |
| `AlertMessage` | devices | dashboard | every message |
| `DeviceCommandMessage` | app | one device | `subscribe(to: device_id)` |
| `DashboardStatusMessage` | dashboard | app | `subscribe(broadcast: true, from: 'dashboard')` |

The steps and what each one verifies:

1. Everybody subscribes. `subscribe` returns once Redis has confirmed, and the four channels are inside the namespace.
2. Devices publish readings and alerts. Each `publish` returns a successful `PublishResult` and the dashboard receives all of them.
3. The app sends one command to each device. Each device receives only the command addressed to it.
4. The dashboard broadcasts a summary and the app receives it.
5. A message with an invalid value is rejected: `publish` raises `SmartMessage::Errors::ValidationError`.
6. After `disconnect`, `publish` raises `SmartMessage::Errors::PublishError` and the message is in the dead letter queue.

## Configuration

One transport for every message class:

```ruby
SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::RedisTransport.new(
    url:       'redis://localhost:6379',
    namespace: 'staging'
  )
end
```

Or one for a single class:

```ruby
class OrderMessage < SmartMessage::Base
  transport SmartMessage::Transport.create(:redis, url: 'redis://localhost:6379', namespace: 'staging')
end
```

There is no default transport. Publishing or subscribing without one raises `SmartMessage::Errors::TransportNotConfigured`.

Options:

| Option | Default | Meaning |
|--------|---------|---------|
| `url:` | `redis://localhost:6379` | Redis URL |
| `db:` | `0` | Database number, used for commands only; it does not isolate channels |
| `namespace:` | none | Channel prefix |
| `reconnect_attempts:` | `5` | Retries for a lost connection |
| `reconnect_delay:` | `1` | Seconds between subscriber reconnects |
| `subscribe_timeout:` | `5` | Seconds to wait for Redis to confirm a subscription |

## Handlers

```ruby
SensorDataMessage.subscribe                          # calls SensorDataMessage.process(message)
SensorDataMessage.subscribe('Dashboard.record')      # calls Dashboard.record(message)
SensorDataMessage.subscribe { |message| ... }        # a block
DeviceCommandMessage.subscribe(to: 'THERM-001') { |message| ... }
```

A handler receives the decoded message object. Handlers run on a thread pool, so code that waits for a result polls with a deadline (see `wait_until` in `support.rb`) instead of sleeping for a fixed time.

## Connection lifecycle

- `subscribe` returns once Redis has confirmed the subscription, or raises `SmartMessage::Errors::TransportError` after `subscribe_timeout` seconds.
- After `disconnect`, publishing and subscribing raise until `connect` is called. `connect` resubscribes the channels that still have handlers.
- A message that could not be published is written to the dead letter queue (`config.dlq_path`).

## Watching the channels

```bash
redis-cli PUBSUB CHANNELS 'sm_example_*'
redis-cli PSUBSCRIBE 'sm_example_*'
```

## Trying it across processes

Give both processes the same namespace. Start the subscriber first, because a message published before the subscriber is connected is not delivered.

```ruby
# subscriber.rb
require 'smart_message'
require_relative 'messages/sensor_data_message'

SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::RedisTransport.new(namespace: 'my_home')
end

SensorDataMessage.subscribe { |reading| puts "#{reading.device_id}: #{reading.value} #{reading.unit}" }
sleep
```

```ruby
# publisher.rb
require 'smart_message'
require_relative 'messages/sensor_data_message'

SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::RedisTransport.new(namespace: 'my_home')
end

SensorDataMessage.new(
  device_id: 'THERM-001', device_type: 'thermostat', sensor_type: 'temperature',
  value: 21.5, unit: 'celsius', from: 'THERM-001'
).publish
```

## See also

- [Memory examples](../memory/) for an in-process transport that needs no server
- [File examples](../file/) for the append-only JSON Lines transport
