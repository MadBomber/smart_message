# Circuit Breakers

A circuit breaker stops calling something that keeps failing. SmartMessage builds its circuits on the [BreakerMachines](https://github.com/seuros/breaker_machines) gem and keeps two kinds:

| Circuit | Scope | Default threshold | Default reset |
|---------|-------|-------------------|---------------|
| Transport publish | **one per transport instance** | 5 failures within 30 seconds | try again after 15 seconds |
| Message processor | **one per handler per message class** | 3 failures within 60 seconds | try again after 30 seconds |

Every circuit has its own in-memory state. A failure in one never opens another: a handler that fails does not stop other handlers, and one transport's failures do not stop another transport.

A circuit is closed (calls go through), open (calls are rejected without being made), or half-open (after the reset time, a trial call decides whether it closes again).

## The transport circuit

`transport.publish` runs the actual send inside the transport's circuit.

- A failing send raises its own error.
- Once the threshold is reached the circuit opens, and further publishes on that transport raise `BreakerMachines::CircuitOpenError` without contacting the medium.

Through `message.publish` both cases are recorded as that transport's failed outcome in the [`PublishResult`](publishing.md) and the message is written to the [dead letter queue](dead-letter-queue.md).

```ruby
transport.transport_circuit_stats
# => { transport_publish: { status: :closed, closed: true, open: false, half_open: false, last_error: nil, stats: {...} } }

transport.reset_transport_circuits!   # close it and forget its failures
```

## The handler circuits

The dispatcher runs each handler inside the circuit for that handler and message class, named `"<MessageClass>:<handler id>"`.

- A handler that raises counts as a failure, and its message goes to the dead letter queue.
- While the circuit is open the handler is not called. Each message it would have received goes to the dead letter queue with a `BreakerMachines::CircuitOpenError`, and any [deduplication](message-deduplication.md) reservation is released, so those messages can be replayed once the cause is fixed.

```ruby
dispatcher = OrderMessage.transport.dispatcher

dispatcher.circuit_breaker_stats
# => { "OrderMessage:OrderMessage.process" => { status: :open, closed: false, open: true, half_open: false, last_error: #<RuntimeError ...>, stats: {...} } }

dispatcher.reset_circuit_breakers!('OrderMessage:OrderMessage.process')   # one circuit
dispatcher.reset_circuit_breakers!                                        # all of them
```

A circuit is created the first time its handler runs and discarded when the handler is unsubscribed.

## Circuit events in the log

When a circuit opens, closes, or half-opens, BreakerMachines reports it with a line such as `[BreakerMachines] Circuit 'OrderMessage:OrderMessage.process' opened`. SmartMessage sends those lines to its own logger: opening is logged at `warn`, the others at `info`. With no logger configured nothing is written.

If your application gives BreakerMachines a logger of its own (`BreakerMachines.logger = ...`) before it loads SmartMessage's circuit breakers, that logger is kept. To drop the events altogether:

```ruby
require 'breaker_machines'

BreakerMachines.configure { |config| config.log_events = false }
```

## Changing the thresholds

Pass `circuit_breaker:` when you create a transport. Give only the values you want to change:

```ruby
transport = SmartMessage::Transport.create(
  :redis,
  namespace: 'production',
  circuit_breaker: {
    transport_publish: { threshold: { failures: 10, within: 60 }, reset_after: 30 },
    message_processor: { threshold: { failures: 5 } }
  }
)
```

`message_processor` applies to every handler circuit of that transport's dispatcher. If you build the dispatcher yourself, pass the options to it: `SmartMessage::Dispatcher.new({ message_processor: { reset_after: 10 } })`.

The defaults are in `SmartMessage::CircuitBreaker::DEFAULT_CONFIGS`.

## Retries: `with_retries`

`SmartMessage::CircuitBreaker.with_retries` is a bounded retry loop with exponential backoff. It is independent of the circuits; use it around a call that may fail transiently.

```ruby
result = SmartMessage::CircuitBreaker.with_retries(max_retries: 3, base_delay: 0.5, max_delay: 10) do |attempt|
  message.publish
end
```

| Option | Default | Meaning |
|--------|---------|---------|
| `max_retries` | `3` | Retries after the first attempt |
| `base_delay` | `1` | Seconds before the first retry; doubles each time |
| `max_delay` | `30` | Upper bound for one delay |
| `on` | `[StandardError]` | Exception classes worth retrying |
| `sleeper` | `Kernel.method(:sleep)` | How to wait; replace it in tests |

The block receives the attempt number, starting at 0. The block's value is returned. When every attempt fails, the last error is raised.

Put `with_retries` around a circuit-protected call, not inside one, so that each attempt counts against the circuit. Limit `on:` to errors that can succeed on a retry; retrying a `ValidationError` is pointless:

```ruby
SmartMessage::CircuitBreaker.with_retries(on: [SmartMessage::Errors::PublishError]) { message.publish }
```

Note that every failed attempt of `message.publish` writes a dead letter queue entry.

## Using circuits in your own code

Build a standalone circuit:

```ruby
circuit = SmartMessage::CircuitBreaker.build(
  'inventory-api',
  { threshold: { failures: 3, within: 60 }, reset_after: 30 }
)

circuit.wrap { InventoryApi.reserve(sku) }   # raises the block's error, or BreakerMachines::CircuitOpenError

SmartMessage::CircuitBreaker.available?(circuit)   # => false while it is open
SmartMessage::CircuitBreaker.stats(circuit)        # => { name:, state:, failure_count:, success_count:, last_failure_at:, opened_at:, last_error: }
SmartMessage::CircuitBreaker.reset!(circuit)
```

A circuit built this way has no fallback: the caller decides what to do with the error.

For a class that uses the BreakerMachines DSL (`circuit(:name).wrap { ... }`), `SmartMessage::CircuitBreaker.configure_for(klass)` adds the two default circuits, and `SmartMessage::CircuitBreaker::Fallbacks` provides fallback procs. A fallback proc receives the error only and is evaluated on the object that owns the circuit:

```ruby
class PaymentService
  include BreakerMachines::DSL

  attr_accessor :current_message

  circuit :gateway do
    threshold failures: 3, within: 60
    reset_after 30
    fallback SmartMessage::CircuitBreaker::Fallbacks.dead_letter_queue { current_message }
  end

  def charge(message)
    self.current_message = message
    circuit(:gateway).wrap { Gateway.charge(message.amount) }
  end
end
```

`Fallbacks.dead_letter_queue(dlq = nil) { message }` stores the message in the dead letter queue and returns `{ circuit_breaker: { state:, rejected:, error:, error_class:, timestamp:, sent_to_dlq: } }`. `Fallbacks.graceful_degradation(response)` returns the same shape with `degraded_response:`.

## A complete program

```ruby
require 'smart_message'
require 'tmpdir'

SmartMessage.configure do |config|
  config.dlq_path = File.join(Dir.mktmpdir, 'dead_letters.jsonl')
end

transport = SmartMessage::Transport::MemoryTransport.new(
  circuit_breaker: { message_processor: { threshold: { failures: 2, within: 60 }, reset_after: 30 } }
)

# messages/sync_message.rb
class SyncMessage < SmartMessage::Base
  from 'sync'
  property :n

  @calls = 0

  class << self
    attr_accessor :calls

    def process(_message)
      self.calls += 1
      raise 'remote system is down'
    end
  end
end

SyncMessage.transport(transport)
SyncMessage.subscribe

5.times do |n|
  SyncMessage.new(n: n).publish
  sleep 0.05 until transport.dispatcher.status[:in_flight].zero?
end
SmartMessage.shutdown

circuit = transport.dispatcher.circuit_breaker_stats['SyncMessage:SyncMessage.process']
errors  = SmartMessage::DeadLetterQueue.default.entries.map { |entry| entry[:error][/\A[\w:]+/] }.tally

puts <<~REPORT
  handler calls: #{SyncMessage.calls}
  circuit open:  #{circuit[:open]}
  dead letters:  #{errors}
REPORT
```

The handler is called twice. The circuit then opens, and the remaining three messages go to the dead letter queue without the handler being called. The output also has the BreakerMachines line announcing that the circuit opened.
