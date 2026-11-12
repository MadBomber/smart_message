# Memory Transport

`SmartMessage::Transport::MemoryTransport` keeps everything inside the process. It is meant for tests and local development.

## Delivery semantics

- **In-process only.** A published message is delivered to the handlers subscribed on the same transport instance. Nothing is sent to another process.
- With `auto_process: true` (the default), `publish` hands the message to the dispatcher immediately. Handlers run on the dispatcher's thread pool.
- With `auto_process: false`, messages are stored and delivered only when you call `process_all`.
- Stored messages live in memory, are capped at `max_messages` (oldest dropped first), and are lost when the process ends.

## Options

```ruby
SmartMessage::Transport::MemoryTransport.new(
  auto_process:   true,   # deliver to subscribers on publish
  store_messages: nil,    # keep published messages; default: only when auto_process is false
  max_messages:   1000,   # how many stored messages to keep
  serialize:      true    # encode on publish and decode on delivery
)

SmartMessage::Transport.create(:memory, auto_process: false)
```

| Option | Default | Meaning |
|--------|---------|---------|
| `auto_process` | `true` | Deliver to subscribers as part of `publish` |
| `store_messages` | `nil` | Keep published messages for `all_messages` and `process_all`. `nil` means "only when `auto_process` is false". |
| `max_messages` | `1000` | Upper bound on stored messages |
| `serialize` | `true` | Encode to JSON on publish and decode on delivery, as a real transport does. With `false`, handlers receive copies of the published object, and type changes caused by serialization go unnoticed. |

Leave `serialize` on in tests: it makes the memory transport behave like the others, so a property that does not survive JSON (a `Time`, a Symbol) shows up in the test and not in production.

## Stored messages

```ruby
transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)

transport.all_messages     # => [{ message_class: "OrderMessage", payload: "{...}", published_at: Time }, ...]
transport.messages         # alias
transport.message_count    # => 2
transport.process_all      # deliver every stored message, remove it, return how many
transport.clear_messages   # discard stored messages
```

`payload` is the serialized String (or, with `serialize: false`, a copy of the message object). To get a message back from a stored entry:

```ruby
entry   = transport.all_messages.first
message = transport.decode_message(entry[:payload])
```

`process_all` removes what it delivers, so calling it twice does not deliver anything twice.

## A complete program

```ruby
require 'smart_message'

# messages/order_message.rb
class OrderMessage < SmartMessage::Base
  from 'order-service'
  property :order_id, required: true

  def self.process(message)
    puts "processing #{message.order_id}"
  end
end

transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
OrderMessage.transport(transport)
OrderMessage.subscribe

OrderMessage.new(order_id: 'ORD-1').publish
OrderMessage.new(order_id: 'ORD-2').publish

puts "stored before: #{transport.message_count}"   # 2: nothing delivered yet
delivered = transport.process_all
SmartMessage.shutdown                               # wait for the handlers

puts "delivered: #{delivered}, stored after: #{transport.message_count}"
```

## In tests

Create a transport per test so that subscriptions and stored messages do not leak between tests:

```ruby
class OrderMessageTest < Minitest::Test
  def setup
    @transport = SmartMessage::Transport::MemoryTransport.new(auto_process: false)
    OrderMessage.transport(@transport)
  end

  def teardown
    OrderMessage.reset_transport
  end

  def test_publishes_one_message
    OrderMessage.new(order_id: 'ORD-1').publish

    assert_equal 1, @transport.message_count
    assert_equal 'ORD-1', @transport.decode_message(@transport.all_messages.first[:payload]).order_id
  end
end
```

To test a handler, call it directly with a message (`OrderMessage.process(OrderMessage.new(order_id: 'ORD-1'))`), or publish with `auto_process: true` and call `transport.dispatcher.shutdown` to wait for it.
