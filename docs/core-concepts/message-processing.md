# Handlers

A handler is the code that runs when a subscribed message arrives. You publish instances and subscribe at the class level.

## Kinds of handler

### The default handler

`MessageClass.subscribe` with no argument subscribes the class method `process`:

```ruby
# messages/order_message.rb
class OrderMessage < SmartMessage::Base
  from 'order-service'
  property :order_id, required: true

  def self.process(message)
    Fulfillment.start(message.order_id)
  end
end

OrderMessage.subscribe   # handler id "OrderMessage.process"
```

A class that subscribes this way must define `self.process` (a class method). If it does not, `subscribe` raises `ArgumentError`.

### A named class method

Pass `"ClassName.method_name"`. The method is looked up when a message arrives, so the class can be defined after the subscription. If the class is already defined, `subscribe` checks that it has that class method and raises `ArgumentError` if not. A handler that is not a `"Class.method"` String, a Proc or a block (a Symbol, for example) also raises `ArgumentError`.

```ruby
class OrderAudit
  def self.record(message)
    AuditLog.append(message.to_h)
  end
end

OrderMessage.subscribe('OrderAudit.record')   # handler id "OrderAudit.record"
```

### A block

```ruby
handler_id = OrderMessage.subscribe do |message|
  Metrics.increment('orders')
end
# handler id like "OrderMessage.proc_3f9a1c0b7d2e4a68"
```

### A proc or lambda

```ruby
notify = ->(message) { Notifier.order_placed(message.order_id) }
handler_id = OrderMessage.subscribe(notify)
```

Blocks, procs and lambdas are kept in a process-wide registry under a generated id. Each `subscribe` call registers a new handler, even when you pass the same proc twice.

All forms accept the [filters](message-filtering.md) `from:`, `to:` and `broadcast:`.

## What a handler receives

One argument: the message. Every handler gets its own copy, with its own header and its own nested values, so a handler that changes its message does not affect any other handler.

```ruby
def self.process(message)
  message.order_id               # properties
  message.from                   # addressing
  message.uuid                   # header uuid
  message._sm_header.published_at
end
```

With every shipped transport the message has been through JSON, so some types differ from what was published: a `Time` property arrives as a String, Symbols as Strings, nested Hash keys as Symbols. See [Serializers](../reference/serializers.md).

The message is not validated before the handler is called.

## Where handlers run

On the dispatcher's thread pool, not on the thread that published or received the message. Consequences:

- `publish` returns before handlers have run.
- Handlers for one message, and handlers for different messages, can run at the same time. Shared state needs its own locking.
- Messages are not guaranteed to be handled in the order they were published.
- A program that exits right after publishing should call `SmartMessage.shutdown` to wait for its handlers.

See [Dispatcher](dispatcher.md).

## When a handler fails

A handler that raises (any `StandardError` or `ScriptError`):

- does not affect other handlers of the same message
- has its copy of the message written to the [dead letter queue](../reference/dead-letter-queue.md) with `transport: "handler:<handler id>"`
- has its [deduplication](../reference/message-deduplication.md) reservation released, so a redelivery or a replay is processed again
- counts as a failure against its own [circuit breaker](../reference/circuit-breakers.md)

After repeated failures the handler's circuit opens. While it is open the handler is not called; each message it would have received goes to the dead letter queue.

Nothing is raised to the publisher: a handler failure is visible in the log (when logging is configured), in `SmartMessage::Stats`, and in the dead letter queue.

## Unsubscribing

```ruby
OrderMessage.unsubscribe                       # the default handler, "OrderMessage.process"
OrderMessage.unsubscribe('OrderAudit.record')  # a named handler
OrderMessage.unsubscribe(handler_id)           # a block/proc/lambda, by the id subscribe returned
OrderMessage.unsubscribe!                      # every handler of this class
```

Passing the block/proc/lambda itself instead of its id raises `ArgumentError`. A message already handed to the thread pool still runs its handler after an unsubscribe.

## A complete program

```ruby
require 'smart_message'
require 'tmpdir'

SmartMessage.configure do |config|
  config.transport = SmartMessage::Transport::MemoryTransport.new
  config.dlq_path  = File.join(Dir.mktmpdir, 'dead_letters.jsonl')
end

# messages/task_message.rb
class TaskMessage < SmartMessage::Base
  from 'scheduler'
  property :name, required: true

  def self.process(message)
    puts "default handler: #{message.name}"
  end
end

class TaskAudit
  def self.record(message)
    puts "named handler: #{message.name}"
  end
end

TaskMessage.subscribe
TaskMessage.subscribe('TaskAudit.record')
block_id = TaskMessage.subscribe { |message| puts "block handler: #{message.name}" }
TaskMessage.subscribe(->(message) { raise "lambda handler cannot do #{message.name}" })

TaskMessage.new(name: 'backup').publish
SmartMessage.shutdown

dlq = SmartMessage::DeadLetterQueue.default
puts <<~REPORT
  block handler id:  #{block_id}
  processed:         #{SmartMessage::Stats.get('TaskMessage', 'TaskMessage.process', 'processed')}
  dead letters:      #{dlq.size}
  dead letter error: #{dlq.peek[:error]}
REPORT
```

Three handlers print their line; the fourth raises, and its message is in the dead letter queue.
