# Dead Letter Queue

The dead letter queue (DLQ) is a file that holds messages SmartMessage could not publish or process. It uses the JSON Lines format: one JSON object per line, oldest first. Entries can be inspected, filtered and replayed.

## Where the file is

The default queue uses the first of these that applies:

1. `config.dlq_path`, when you set it
2. the environment variable `SMART_MESSAGE_DLQ_PATH`
3. `$XDG_STATE_HOME/smart_message/dead_letters.jsonl`, when `XDG_STATE_HOME` is set
4. `~/.local/state/smart_message/dead_letters.jsonl`

```ruby
SmartMessage.configure do |config|
  config.dlq_path = '/var/lib/my_app/dead_letters.jsonl'
end

SmartMessage.configuration.dlq_path    # => "/var/lib/my_app/dead_letters.jsonl"
SmartMessage::DeadLetterQueue.default  # the queue at that path
```

The path is always stored as an absolute path, so it never depends on the working directory. The directory is created when the queue is first used. A sidecar file `<path>.lock` appears next to the queue file; it is the lock described below.

`SmartMessage::DeadLetterQueue.configure_default(path)` is a shortcut that sets `config.dlq_path` and returns the queue.

You can also work with any queue file directly:

```ruby
queue = SmartMessage::DeadLetterQueue.new('/tmp/payments_dlq.jsonl')
```

## What lands in it

SmartMessage writes to the default queue in five situations:

| Situation | `transport` field of the entry | `error` field |
|-----------|-------------------------------|---------------|
| A transport failed to publish the message | the transport's class name | the transport's error |
| A received payload could not be decoded (not an envelope, unknown message class, class does not match the channel) | the transport's class name | the decode error |
| A handler raised | `handler:<handler id>` | the handler's error |
| A handler's circuit breaker was open, so the handler was not called | `handler:<handler id>` | `BreakerMachines::CircuitOpenError: ...` |
| A handler was still running when the shutdown timeout expired and was killed | `handler:<handler id>` | `SmartMessage::Errors::Error: Dispatcher shut down before the handler finished` |

A publish that fails on several transports writes one entry per failed transport. A message with several handlers writes one entry per failed handler.

If writing to the queue itself fails, that is logged at error level and the original error is still raised or recorded.

## Entry format

```json
{
  "id": "8a4c3c53-5d1b-4d0c-9a57-3e0b7c6f4d11",
  "timestamp": "2026-11-11T10:15:30.123-06:00",
  "header": { "uuid": "0b0e6f0c-...", "message_class": "OrderMessage", "published_at": "2026-11-11T10:15:30.123456-06:00", "publisher_pid": 4242, "version": 1, "from": "order-service", "serializer": "SmartMessage::Serializer::Json" },
  "payload": "{\"_sm_header\":{...},\"order_id\":\"ORD-1\"}",
  "payload_format": "json",
  "error": "RuntimeError: inventory service is down",
  "retry_count": 0,
  "transport": "handler:OrderMessage.process",
  "stack_trace": "..."
}
```

| Field | Meaning |
|-------|---------|
| `id` | Unique id of the entry |
| `timestamp` | When the entry was written |
| `header` | The message header, for reading and filtering. For a payload that could not be decoded, only `message_class` (the channel it arrived for, or `"Unknown"`). Replay uses the header inside `payload`, and fails when that header names a different class than this `message_class`. |
| `payload` | The serialized message, including its header |
| `payload_format` | Serializer of the payload; `"json"` |
| `error` | `"ErrorClass: message"` |
| `retry_count` | Number of failed replays |
| `transport` | Where it failed (see the table above) |
| `stack_trace` | Backtrace, when there was one |

Methods that return entries return Hashes with Symbol keys.

## Inspecting

```ruby
dlq = SmartMessage::DeadLetterQueue.default

dlq.size                        # number of lines in the file
dlq.empty?
dlq.peek                        # oldest entry, not removed
dlq.entries                     # every valid entry, oldest first
dlq.inspect_messages(limit: 10) # the first 10 entries

dlq.filter_by_class('OrderMessage')
dlq.filter_by_error_pattern(/timeout/i)       # a Regexp or a String
dlq.export_range(Time.now - 3600, Time.now)   # by entry timestamp

dlq.statistics
# => { total: 3, by_class: { "OrderMessage" => 3 }, by_error: { "RuntimeError: ..." => 3 }, corrupt: 0 }
```

## Replaying

Replay rebuilds the message from the entry, with its original header and the same UUID, and publishes it again.

```ruby
dlq.replay_one                # the oldest entry
dlq.replay_batch(10)          # the oldest 10
dlq.replay_all                # everything in the queue right now

dlq.replay_one(transport)     # each takes an optional transport to publish on instead
dlq.replay_batch(10, transport)
dlq.replay_all(transport)
```

`replay_one` returns `{ success: true, message: }` or `{ success: false, error: }`. `replay_batch` and `replay_all` return `{ success: <count>, failed: <count>, errors: [...] }`.

Replay semantics:

- **Replay publishes; it does not call a handler.** The message goes out on its class's transports (or the override) and reaches whoever is subscribed, like any published message. This is true for handler failures too: replaying an entry whose `transport` is `handler:OrderMessage.process` republishes the message, and every current subscriber of the class receives it, not only the handler that failed. Enable [deduplication](message-deduplication.md) if the other handlers must not process it again; the failed handler's reservation was released, so it will run.
- **An entry is removed only after it has been published again.** A replay that fails leaves the entry in the queue, with `retry_count` raised by one and `error` replaced by `"Replay failed: ..."`.
- **The message class must be loaded.** Replay needs the `SmartMessage::Base` subclass named in the entry, and that class needs a transport (or pass one).
- **The message is validated again,** because replay calls `publish`.
- **An undecodable payload cannot be replayed as it is.** Its replay fails for the same reason it could not be decoded, and it stays in the queue for inspection.
- If the replay publish fails on a transport, `publish` writes a new entry for that failure as usual.

`dequeue` removes and returns the oldest entry without publishing it. `clear` deletes the queue file.

## Adding entries yourself

```ruby
dlq.enqueue(message, error: 'Rejected by the fraud check', transport: 'manual')

dlq.enqueue_raw(
  message_class: 'OrderMessage',
  payload:       raw_string,
  error_info:    { error: 'Could not parse', transport: 'import-script' }
)
```

`enqueue` accepts `:error`, `:retry_count`, `:transport` and `:stack_trace`. `enqueue_raw` stores a payload untouched, for bytes that could not be turned into a message; its `error_info` also accepts `:serializer`.

## Concurrency and durability

- Every read-modify-write runs under an exclusive lock on `<file>.lock`, so several threads and several processes can share one queue file.
- Appends are flushed to disk (`fsync`).
- Rewrites (after `dequeue` or a replay) go to a temporary file that is then renamed over the queue, so a crash does not leave a half-written queue.
- A corrupt line does not stop later lines from being read. `statistics[:corrupt]` counts corrupt lines; `dequeue` drops the corrupt lines ahead of the entry it returns and logs a warning.

## A complete program

```ruby
require 'smart_message'
require 'tmpdir'

SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::MemoryTransport.new
  config.dlq_path  = File.join(Dir.mktmpdir, 'dead_letters.jsonl')
end

# messages/payment_message.rb
class PaymentMessage < SmartMessage::Base
  from 'checkout'
  property :amount, required: true

  @gateway_up = false

  class << self
    attr_accessor :gateway_up

    def process(message)
      raise 'payment gateway is down' unless gateway_up

      puts "charged #{message.amount}"
    end
  end
end

PaymentMessage.subscribe
PaymentMessage.new(amount: 25).publish

dispatcher = PaymentMessage.transport.dispatcher
sleep 0.05 until dispatcher.status[:in_flight].zero?   # wait for the handler to fail

dlq   = SmartMessage::DeadLetterQueue.default
entry = dlq.peek
puts <<~REPORT
  queue file: #{dlq.file_path}
  entries:    #{dlq.size}
  error:      #{entry[:error]}
  failed in:  #{entry[:transport]}
REPORT

# Fix the problem, then replay
PaymentMessage.gateway_up = true
outcome = dlq.replay_one

SmartMessage.shutdown
puts "replayed: #{outcome[:success]}, entries left: #{dlq.size}"
```
