# Dispatcher

`SmartMessage::Dispatcher` routes incoming messages to subscribed handlers. Each transport instance creates its own dispatcher unless you pass one in, so in most programs you never build a dispatcher yourself.

For each message it:

1. finds the subscriptions for the message class
2. drops the subscriptions whose [filters](message-filtering.md) do not match
3. reserves the message UUID for each handler when [deduplication](../reference/message-deduplication.md) is enabled, and skips handlers that have already seen it
4. gives each remaining handler **its own copy of the message** and posts it to the thread pool
5. runs the handler inside that handler's [circuit breaker](../reference/circuit-breakers.md)
6. on failure, releases the deduplication reservation and writes the message to the [dead letter queue](../reference/dead-letter-queue.md)

## The thread pool is bounded

Each dispatcher has one thread pool with a fixed maximum size and a bounded queue.

| Setting | Default | Meaning |
|---------|---------|---------|
| `config.dispatcher_max_threads` | `[CPU count * 2, 4].max` | Handler threads per dispatcher |
| `config.dispatcher_max_queue` | `1000` | Handler calls that may wait for a thread |

```ruby
SmartMessage.configure do |config|
  config.dispatcher_max_threads = 8
  config.dispatcher_max_queue   = 200
end
```

A dispatcher reads these when it is created, so set them before you create transports.

When all threads are busy and the queue is full, the thread that is delivering the message (the publisher with the memory transport, the subscriber thread with Redis, the poller with the file transport) runs the handler itself. That slows the source down instead of letting the queue grow without limit. No message is dropped.

To give one transport its own limits, build its dispatcher:

```ruby
dispatcher = SmartMessage::Dispatcher.new(max_threads: 2, max_queue: 50)
transport  = SmartMessage::Transport::MemoryTransport.new(dispatcher: dispatcher)
```

Several transports can share one dispatcher the same way; they then share subscriptions, the pool, and the deduplication queues.

## Each handler gets its own copy

The dispatcher calls `message.dup` for every handler. A copy has its own header and its own nested Hashes, Arrays and Strings.

```ruby
OrderMessage.subscribe { |message| message.items << 'changed by handler one' }
OrderMessage.subscribe { |message| message.items.size }   # never sees handler one's change
```

## Handler isolation

A handler that raises does not stop or affect the other handlers of the same message. Its failure is logged, counted in `SmartMessage::Stats` as `failed`, and the message is dead-lettered with `transport: "handler:<handler id>"`. An exception never escapes a pool thread.

## Shutdown

```ruby
SmartMessage.shutdown(timeout: 10)   # => true when every handler finished in time
```

`SmartMessage.shutdown` stops every live dispatcher. Each one stops accepting work on its pool and waits for the handlers that are queued or running. The timeout is a total budget shared by all dispatchers; without an argument it is `config.shutdown_timeout` (default 5 seconds).

A handler that is still running when the time is up is killed. Its message is logged and written to the dead letter queue with the error `Dispatcher shut down before the handler finished`, so it can be replayed.

SmartMessage registers `SmartMessage.shutdown` once with `at_exit`. Call it yourself when you want to choose the moment or the timeout, or to check the result:

```ruby

at_exit do
  drained = SmartMessage.shutdown(timeout: 30)
  warn 'some handlers were killed; see the dead letter queue' unless drained
end
```

A single dispatcher can be shut down with `dispatcher.shutdown(timeout: 5)`.

After a shutdown the pool is closed. A message that arrives afterwards still has its handlers run, on the thread that delivers it.

Shutting down the dispatcher does not disconnect transports. Call `transport.disconnect` to stop a Redis subscriber or a file poller.

## Status and statistics

```ruby
dispatcher = OrderMessage.transport.dispatcher

dispatcher.status
# => { scheduled_task_count: 12, completed_task_count: 12, queue_length: 0,
#      length: 4, in_flight: 0, running: true }

dispatcher.subscribers            # => { "OrderMessage" => [{ subscriber_id:, process_method:, filters: }, ...] }
dispatcher.circuit_breaker_stats  # => { "OrderMessage:OrderMessage.process" => { status: :closed, ... } }
dispatcher.ddq_stats              # => { "OrderMessage:OrderMessage.process" => { size: 100, ... } }

SmartMessage::Stats.get('OrderMessage', 'OrderMessage.process', 'routed')
SmartMessage::Stats.get('OrderMessage', 'OrderMessage.process', 'processed')
SmartMessage::Stats.get('OrderMessage', 'OrderMessage.process', 'failed')
SmartMessage::Stats.get('OrderMessage', 'OrderMessage.process', 'duplicate')
```

`in_flight` is the number of handler calls that have been posted and have not finished.

## A complete program

```ruby
require 'smart_message'
require 'tmpdir'

SmartMessage.configure do |config|
  config.dispatcher_max_threads = 2
  config.dispatcher_max_queue   = 10
  config.transport = SmartMessage::Transport::MemoryTransport.new
  config.dlq_path  = File.join(Dir.mktmpdir, 'dead_letters.jsonl')
end

# messages/job_message.rb
class JobMessage < SmartMessage::Base
  from 'scheduler'
  property :seconds, required: true

  def self.process(message)
    sleep message.seconds
    puts "finished a #{message.seconds}s job"
  end
end

JobMessage.subscribe
JobMessage.new(seconds: 0.1).publish
JobMessage.new(seconds: 5).publish

drained = SmartMessage.shutdown(timeout: 1)

entry = SmartMessage::DeadLetterQueue.default.peek
puts <<~REPORT
  drained in time: #{drained}
  dead letters:    #{SmartMessage::DeadLetterQueue.default.size}
  reason:          #{entry[:error]}
REPORT
```

The short job finishes. The long one is killed after one second and its message is in the dead letter queue.
