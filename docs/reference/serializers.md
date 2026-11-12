# Serializers

A serializer turns a message Hash into a String and back. Each transport owns one serializer and uses it for everything it sends and receives.

SmartMessage ships one serializer: `SmartMessage::Serializer::Json`. It is the default for every transport.

## The wire format

A message on the wire is one flat JSON object: the message's properties plus the header under `_sm_header`.

```json
{
  "_sm_header": {
    "uuid": "0b0e6f0c-4f6e-4a57-9b1e-3b6a2a6f2f10",
    "message_class": "OrderMessage",
    "published_at": "2026-11-11T10:15:30.123456-06:00",
    "publisher_pid": 4242,
    "version": 1,
    "from": "order-service",
    "serializer": "SmartMessage::Serializer::Json"
  },
  "order_id": "ORD-1",
  "amount": 99.99
}
```

Header fields that are `nil` are left out. Header fields the receiving version does not know are kept in `header.extensions` and written back out when the message is published again, so an older consumer can pass on a message from a newer publisher without losing them.

## Type changes on a JSON round trip

JSON has fewer types than Ruby, so a value can come back as a different type. Every shipped transport serializes (the memory transport too, unless you pass `serialize: false`), so this applies to what handlers receive.

| Published as | Received as |
|--------------|-------------|
| `String`, `Integer`, `Float`, `true`, `false`, `nil` | unchanged |
| `Time`, `DateTime` | ISO 8601 `String` with microseconds, such as `"2026-11-11T10:15:30.123456-06:00"` |
| `Date` | ISO 8601 `String`, such as `"2026-11-11"` |
| `Symbol` | `String` |
| `BigDecimal` | `String` in plain notation, such as `"1.0"` |
| any other object | its `to_h` (converted the same way) when it has one, else its `to_s` |
| `Hash` keys (String or Symbol) | `Symbol`, at every level |
| `Array` | `Array`, elements converted as above |

The encoding is the same in every process, whatever JSON extensions are loaded.

The header's `published_at` is the exception: it is restored to a `Time` automatically.

## Restoring a type with `coerce_key`

Declare a coercion on the message class. It runs whenever the property is assigned, including when a received message is rebuilt, so the handler sees the type you want.

```ruby
coerce_key :placed_at, ->(value) { value.is_a?(String) ? Time.parse(value) : value }
```

The `is_a?(String)` guard matters: the same coercion also runs on the publishing side, where the value is already a `Time`.

A complete program:

```ruby
require 'smart_message'
require 'time'
require 'date'
require 'bigdecimal'

# messages/invoice_message.rb
class InvoiceMessage < SmartMessage::Base
  from 'billing'
  transport SmartMessage::Transport::MemoryTransport.new

  property :issued_at
  property :due_on
  property :total
  property :status
  property :raw_time
  property :lines

  coerce_key :issued_at, ->(value) { value.is_a?(String) ? Time.parse(value) : value }
  coerce_key :due_on,    ->(value) { value.is_a?(String) ? Date.parse(value) : value }
  coerce_key :total,     ->(value) { value.is_a?(String) ? BigDecimal(value) : value }
  coerce_key :status,    ->(value) { value.respond_to?(:to_sym) ? value.to_sym : value }

  def self.process(message)
    puts <<~RECEIVED
      issued_at: #{message.issued_at.class}   (coerced)
      due_on:    #{message.due_on.class}   (coerced)
      total:     #{message.total.class}   (coerced)
      status:    #{message.status.inspect}   (coerced)
      raw_time:  #{message.raw_time.class}   (no coercion: a String)
      lines:     #{message.lines.inspect}   (keys are Symbols, values converted)
    RECEIVED
  end
end

InvoiceMessage.subscribe
InvoiceMessage.new(
  issued_at: Time.now,
  due_on:    Date.today + 30,
  total:     BigDecimal('99.50'),
  status:    :open,
  raw_time:  Time.now,
  lines:     [{ 'sku' => 'A-1', kind: :widget }]
).publish

SmartMessage.shutdown
```

For nested structures, coerce the whole property (a lambda that maps over the Array, for example).

## Errors

- A message that cannot be encoded raises `SmartMessage::Errors::SerializationError`. `publish` records it as that transport's failure.
- A payload that cannot be decoded raises `SmartMessage::Errors::DecodeError`. On receive, the payload is stored in the [dead letter queue](dead-letter-queue.md).

Serializers are not wrapped in a circuit breaker.

## Using the serializer directly

```ruby
serializer = SmartMessage::Serializer::Json.new

payload = serializer.encode({ order_id: 'ORD-1', placed_at: Time.now })   # => String
serializer.decode(payload)                                                # => { order_id: "ORD-1", placed_at: "2026-..." }

SmartMessage::Serializer::Json.jsonify(:open)        # => "open"
SmartMessage::Serializer.default                     # => SmartMessage::Serializer::Json
SmartMessage::Serializer.for('json')                 # => SmartMessage::Serializer::Json
```

To encode or decode a whole message with its header, use the transport (`transport.encode_message(message)`, `transport.decode_message(payload)`) or `SmartMessage::Envelope`.

## Writing a serializer

Subclass `SmartMessage::Serializer::Base` and implement two private methods. `do_encode` receives a Hash with Symbol keys, including `:_sm_header`, and returns a String. `do_decode` receives the String and returns a Hash; the header must come back under `_sm_header` (String or Symbol key).

Any error they raise is wrapped in `SerializationError` or `DecodeError`.

```ruby
require 'smart_message'
require 'json'

# JSON, indented for people to read
class PrettyJsonSerializer < SmartMessage::Serializer::Base
  private

  def do_encode(message_hash)
    JSON.pretty_generate(SmartMessage::Serializer::Json.jsonify(message_hash))
  end

  def do_decode(payload)
    JSON.parse(payload, symbolize_names: true)
  end
end

# messages/greeting_message.rb
class GreetingMessage < SmartMessage::Base
  from 'greeter'
  transport SmartMessage::Transport::StdoutTransport.new(serializer: PrettyJsonSerializer.new)
  property :text
end

GreetingMessage.new(text: 'hello').publish
```

A serializer is given to a transport with the `serializer:` option. Both ends of a transport must use compatible serializers. The file transport expects one message per line, so a serializer used with it must not emit newlines.
