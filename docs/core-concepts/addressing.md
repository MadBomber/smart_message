# Addressing

Every message header has three addressing fields. Their values are entity ids: Strings your application chooses, such as service names.

| Field | Required | Meaning |
|-------|----------|---------|
| `from` | yes | The entity sending the message |
| `to` | no | The intended recipient. `nil` means a broadcast. |
| `reply_to` | no | Where a reply should be sent |

Addressing does not change where a transport delivers a message: every subscriber of the message class on that transport receives it. Addressing is what [subscription filters](message-filtering.md) match on, and what handlers read.

`from`, `to` and `reply_to` are reserved names. They live in the header and cannot be declared as properties.

## Class defaults

```ruby
# messages/order_message.rb
class OrderMessage < SmartMessage::Base
  from     'order-service'
  to       'fulfillment-service'
  reply_to 'order-service'

  property :order_id, required: true
end
```

The same thing with the header block:

```ruby
class OrderMessage < SmartMessage::Base
  header do
    from     'order-service'
    to       'fulfillment-service'
    reply_to 'order-service'
  end

  property :order_id, required: true
end
```

`header` at class level takes a block and nothing else; any other call raises `ArgumentError`.

Class defaults are inherited by subclasses. A subclass that sets its own value does not change its parent.

```ruby
OrderMessage.from                # => "order-service"
OrderMessage.to_configured?      # => true
OrderMessage.reply_to_missing?   # => false
OrderMessage.reset_to            # forget this class's own value
```

## Per message

Pass addressing to `new`, or set it afterwards. An instance keeps its addressing in its header.

```ruby
order = OrderMessage.new(order_id: 'ORD-1', to: 'express-fulfillment')

order.from                      # => "order-service"        (class default)
order.to                        # => "express-fulfillment"  (given to new)

order.to = 'backup-fulfillment'           # setter
order.to('fulfillment-eu').reply_to('eu') # with an argument: sets and returns the message

order._sm_header.to             # => "fulfillment-eu"
order.reset_to                  # back to the class default
order.to                        # => "fulfillment-service"
```

A message with no `from` (none on the class, none given) fails validation:

```ruby
class PingMessage < SmartMessage::Base
  property :text
end

ping = PingMessage.new(text: 'hello')
ping.valid?                     # => false
ping.validation_errors.first    # => { property: :from, value: nil, message: "From entity ID is required ...", source: "header" }
ping.from('console').valid?     # => true
```

## Patterns

### Point to point

Set `to`. Receivers subscribe with a `to:` filter so that each one handles only its own messages.

```ruby
OrderMessage.subscribe(to: 'fulfillment-service')

OrderMessage.new(order_id: 'ORD-1', to: 'fulfillment-service').publish
```

### Broadcast

Leave `to` unset. Subscribers that want only broadcasts use `broadcast: true`.

```ruby
class MaintenanceNotice < SmartMessage::Base
  from 'ops'
  property :text, required: true
end

MaintenanceNotice.subscribe(broadcast: true)
```

### Request and reply

The requester sets `reply_to`; the responder addresses its reply to it.

```ruby
class PriceRequest < SmartMessage::Base
  property :sku, required: true

  def self.process(message)
    PriceReply.new(sku: message.sku, cents: 1299, from: 'pricing', to: message.reply_to).publish
  end
end
```

A complete version of this pattern is in [Examples](../getting-started/examples.md).
