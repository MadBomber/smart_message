# Publishing

```ruby
result = message.publish
```

`publish` does four things:

1. Calls `validate!`. An invalid message raises `SmartMessage::Errors::ValidationError` and nothing is sent.
2. Raises `SmartMessage::Errors::TransportNotConfigured` when the message has no transport.
3. Sends the message on every configured transport, each one independently.
4. Returns a `SmartMessage::PublishResult`, or raises `SmartMessage::Errors::PublishError` when every transport failed.

## `SmartMessage::PublishResult`

One outcome per transport.

| Method | Returns |
|--------|---------|
| `success?` | `true` when every transport accepted the message |
| `partial?` | `true` when some transports accepted it and some failed |
| `failure?` | `true` when no transport accepted it |
| `outcomes` | every `Outcome`, in transport order |
| `successful` | the outcomes that succeeded |
| `failed` | the outcomes that failed |
| `errors` | the exceptions of the failed outcomes |
| `message_class` | the message class name |
| `uuid` | the message UUID |
| `to_h` | `{ message_class:, uuid:, success:, outcomes: [...] }` |

Each `SmartMessage::PublishResult::Outcome` has:

| Method | Returns |
|--------|---------|
| `transport` | the transport instance |
| `transport_name` | its short class name, such as `"RedisTransport"` |
| `error` | the exception, or `nil` on success |
| `success?`, `failure?` | |
| `to_h` | `{ transport:, success:, error: }` |

A result means "the transport accepted the message". It says nothing about handlers: they run later, on other threads, possibly in other processes.

## `SmartMessage::Errors::PublishError`

Raised when every configured transport failed. `error.result` is the `PublishResult`, so nothing about the failure is lost.

```ruby
begin
  message.publish
rescue SmartMessage::Errors::PublishError => e
  e.message                 # => "All transports failed for OrderMessage: RedisTransport: Connection refused ..."
  e.result.failed.size      # => 1
  e.result.errors.first     # the transport's exception
end
```

With one transport, that is the only failure mode: `publish` either returns a successful result or raises.

## Several transports and partial success

A class or instance with several transports publishes to each. When some succeed and some fail, `publish` **does not raise**. It returns a result with `partial?` true, and you decide whether that is acceptable.

```ruby
result = message.publish

if result.partial?
  result.failed.each do |outcome|
    warn "#{outcome.transport_name} did not get #{result.uuid}: #{outcome.error.message}"
  end
end
```

Check `success?` (or `partial?`) whenever you publish to more than one transport. A caller that ignores the result treats a partial failure as a success.

## Failed publishes go to the dead letter queue

Each transport that fails, in a partial failure or a total one, has the message written to the [dead letter queue](dead-letter-queue.md) with the transport's class name and the error. Replaying the entry publishes the message again.

The transport's own [circuit breaker](circuit-breakers.md) counts the failure. After repeated failures the circuit opens and further publishes on that transport fail immediately with `BreakerMachines::CircuitOpenError`, which is recorded and dead-lettered like any other publish failure.

Publish counts are kept in `SmartMessage::Stats`. Only a publish that reached at least one transport is counted:

```ruby
SmartMessage::Stats.get('OrderMessage', 'publish')
```

## A complete program

One transport that works and one that always fails.

```ruby
require 'smart_message'
require 'tmpdir'

SmartMessage.configure do |config|
  config.dlq_path = File.join(Dir.mktmpdir, 'dead_letters.jsonl')
end

class BrokenTransport < SmartMessage::Transport::Base
  def do_publish(_message_class, _serialized_message)
    raise SmartMessage::Errors::TransportError, 'the broker is unreachable'
  end
end

# messages/order_message.rb
class OrderMessage < SmartMessage::Base
  from 'order-service'
  property :order_id, required: true
end

memory = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
broken = BrokenTransport.new
dlq    = SmartMessage::DeadLetterQueue.default

# Partial success: no exception
OrderMessage.transport([memory, broken])
result = OrderMessage.new(order_id: 'ORD-1').publish

puts <<~REPORT
  success?   #{result.success?}
  partial?   #{result.partial?}
  succeeded: #{result.successful.map(&:transport_name).join(', ')}
  failed:    #{result.failed.map { |outcome| "#{outcome.transport_name} (#{outcome.error.message})" }.join(', ')}
  DLQ size:  #{dlq.size}
REPORT

# Total failure: PublishError
OrderMessage.transport(broken)
begin
  OrderMessage.new(order_id: 'ORD-2').publish
rescue SmartMessage::Errors::PublishError => e
  puts "raised:    #{e.message}"
  puts "DLQ size:  #{dlq.size}"
end
```

## Subscribing with several transports

`MessageClass.subscribe` subscribes on every configured transport. If the same message can arrive over two of them, a handler runs twice. Either subscribe on one transport only, or enable [deduplication](message-deduplication.md) and make the two transports share a dispatcher (`dispatcher:` option) or use the Redis deduplication backend.

## Publishing to a transport directly

`transport.publish(message)` encodes and sends one message on one transport. It returns `true` or raises the transport's own error. It does not validate the message, does not write to the dead letter queue and does not update the publish counter; `message.publish` does those.
