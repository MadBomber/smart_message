# Properties and Validation

A message class declares its content with `property`. `SmartMessage::Base` is a `Hashie::Dash`, so the Hashie options (`default:`, `from:`, `with:`, `transform_with:`, and `coerce_key`) work, and SmartMessage adds `required:`, `validate:`, `validation_message:` and `description:`.

```ruby
# messages/order_message.rb
class OrderMessage < SmartMessage::Base
  description 'A customer order'
  version 2
  from 'order-service'

  property :order_id,
           required: true,
           message: 'order_id is required',
           description: 'Unique order identifier'

  property :amount,
           required: true,
           validate: ->(value) { value.is_a?(Numeric) && value.positive? },
           validation_message: 'amount must be a positive number'

  property :currency,
           default: 'USD',
           validate: %w[USD EUR GBP],
           description: 'ISO 4217 currency code'

  property :note
end
```

## Property options

| Option | Meaning |
|--------|---------|
| `required: true` | The property must not be `nil` when the message is validated. May also be a proc, evaluated on the instance, that returns true when the property is required: `-> { kind == 'physical' }`, or `->(message) { message.kind == 'physical' }` to receive the message. |
| `message:` | Error text when a required property is missing |
| `default:` | Value used when none is given. A proc is called to produce it. |
| `validate:` | A validator (see below) |
| `validation_message:` | Error text when the validator fails |
| `description:` | Documentation for the property |
| `from:`, `with:`, `transform_with:` | Hashie property translation |

## Reading and writing

```ruby
order = OrderMessage.new(order_id: 'ORD-1', amount: 10)

order.order_id          # => "ORD-1"
order[:order_id]        # => "ORD-1"
order['order_id']       # => "ORD-1"
order.note = 'gift'
order.fields            # => #<Set: {:order_id, :amount, :currency, :note}>
order.payload_hash      # => { order_id: "ORD-1", amount: 10, currency: "USD", note: "gift" }
order.to_h              # the same plus :_sm_header, a plain Hash of the header fields
```

`new` accepts keyword arguments or a Hash, with String or Symbol keys. Keys that are not declared properties are ignored. `from`, `to` and `reply_to` are addressing, not properties; they go into the header.

Values are deep-copied when the message is built, so a message never shares nested Hashes, Arrays or Strings with the caller. Nested Hashes keep the keys they were given: only the top level of a message accepts both Strings and Symbols.

## Validation

Nothing is validated in `new`. Validation runs when you call one of these, and `publish` calls `validate!`:

```ruby
order = OrderMessage.new(amount: -5)   # no error

order.valid?              # => false
order.validation_errors
# => [
#   { property: :order_id, value: nil, message: "order_id is required", source: "message" },
#   { property: :amount, value: -5, message: "amount must be a positive number", source: "message" }
# ]

order.validate!           # raises SmartMessage::Errors::ValidationError
```

`validation_errors` returns one Hash per failure. `source` is `"message"` for a property of the message, `"header"` for a header field (a missing `from`, for instance), or `"version_mismatch"`.

`SmartMessage::Errors::ValidationError#errors` holds the same Array, and the exception message lists every failure:

```ruby
begin
  order.publish
rescue SmartMessage::Errors::ValidationError => e
  e.message   # => "OrderMessage#order_id: order_id is required; OrderMessage#amount: amount must be a positive number"
  e.errors.map { |error| error[:property] }   # => [:order_id, :amount]
end
```

Validation covers three things:

1. the message's own properties: required rules, then validators
2. the header: `uuid`, `message_class`, `published_at`, `publisher_pid`, `version` and `from` are required
3. the header version must equal the class version

A validator is skipped when the value is `nil`; whether `nil` is acceptable is the `required:` rule's business. A validator that raises counts as a failed validation.

A message that arrives from a transport is not validated before the handler is called. Call `message.valid?` in the handler if you need to.

### Validator types

| `validate:` value | Passes when |
|-------------------|-------------|
| Proc or lambda | it returns a truthy value; it is evaluated on the message instance, so it can read other properties |
| Symbol | the instance method with that name returns a truthy value for the value |
| Regexp | it matches `value.to_s` |
| Class or Module | `value.is_a?(TheClassOrModule)`, so `Enumerable` or `Comparable` work too |
| Array or Set | it includes the value |
| Range | it covers the value |
| anything else | it equals the value |

```ruby
class ShipmentMessage < SmartMessage::Base
  from 'warehouse'

  property :tracking, validate: /\A[A-Z]{2}\d{9}\z/
  property :weight,   validate: 0.1..500.0
  property :carrier,  validate: %w[ups fedex dhl]
  property :items,    validate: Array
  property :insured
  property :insured_value,
           required: -> { insured },                      # required only when insured
           validate: ->(value) { value <= 10_000 }
end
```

### Inheritance

Required rules, validators and descriptions are inherited. A subclass can add its own or override one of its parent's; it cannot change the parent.

## Reserved property names

The framework reads or defines some names on every message. Declaring a property with one of them raises `SmartMessage::Errors::ReservedPropertyName` when the class is defined:

- `from`, `to`, `reply_to`, `uuid`
- `publish`, `transport`, `transports`, `config`, `logger`
- `validate!`, `valid?`, `validation_errors`
- `to_h`, `to_hash`, `message_header`
- any name starting with `_sm_`

```ruby
class TransferMessage < SmartMessage::Base
  property :from   # raises SmartMessage::Errors::ReservedPropertyName:
                   #   TransferMessage: property name 'from' is reserved by SmartMessage
end

SmartMessage::Base.reserved_property_name?(:to)        # => true
SmartMessage::Base.reserved_property_name?(:_sm_id)    # => true
SmartMessage::Base::RESERVED_PROPERTY_NAMES            # the list
```

`ReservedPropertyName` is an `ArgumentError`.

## Coercion

`coerce_key` (from `Hashie::Extensions::Coercion`) converts a value when it is assigned, both in `new` and afterwards. Its main use is to restore a type that JSON cannot carry:

```ruby
require 'time'

class EventMessage < SmartMessage::Base
  from 'events'
  property :occurred_at
  coerce_key :occurred_at, ->(value) { value.is_a?(String) ? Time.parse(value) : value }
end
```

See [Serializers](../reference/serializers.md) for the list of type changes on a JSON round trip.

## Versions

```ruby
class OrderMessage < SmartMessage::Base
  version 2
end

OrderMessage.version                       # => 2
OrderMessage.new._sm_header.version        # => 2
```

The version is a positive Integer, default 1, inherited by subclasses. A message whose header version differs from its class version fails validation with a `"version_mismatch"` error. Because received messages are not validated automatically, a handler that must reject other versions calls `message.validate!` or compares `message._sm_header.version` itself.

## Descriptions

```ruby
OrderMessage.description                        # => "A customer order"
OrderMessage.property_description(:order_id)    # => "Unique order identifier"
OrderMessage.property_descriptions              # => { order_id: "...", currency: "..." }
OrderMessage.described_properties               # => [:order_id, :currency]
OrderMessage.new.description                    # the class description
```

A class without a description gets `"<ClassName> is a SmartMessage"`. Property descriptions are inherited; the class description is not.

## Pretty printing

```ruby
order.pretty_print                        # properties only
order.pretty_print(include_header: true)  # header, then properties
```

`pretty_print` uses the `amazing_print` gem when it is installed and Ruby's `pp` otherwise.
