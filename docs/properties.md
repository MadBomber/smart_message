# SmartMessage Property System

The SmartMessage property system builds on Hashie::Dash to provide a robust, declarative way to define message attributes. This document covers all available property options and features.

## Table of Contents
- [Basic Property Definition](#basic-property-definition)
- [Property Options](#property-options)
- [Accessing Property Information](#accessing-property-information)
- [Hashie Extensions](#hashie-extensions)
- [Examples](#examples)

## Basic Property Definition

Properties are defined using the `property` method in your message class:

```ruby
class MyMessage < SmartMessage::Base
  property :field_name
end
```

## Property Options

SmartMessage supports all Hashie::Dash property options plus additional features:

### 1. Default Values

Specify a default value for a property when not provided during initialization:

```ruby
class OrderMessage < SmartMessage::Base
  # Static default
  property :status, default: 'pending'

  # Dynamic default using a Proc
  property :created_at, default: -> { Time.now }

  # Default array
  property :items, default: []
end

order = OrderMessage.new
order.status     # => 'pending'
order.created_at # => Current time
order.items      # => []
```

### 2. Required Properties

Mark properties as required to ensure they're provided during initialization:

```ruby
class PaymentMessage < SmartMessage::Base
  property :payment_id, required: true
  property :amount, required: true
  property :note  # Optional
end

# This raises ArgumentError: The property 'payment_id' is required
PaymentMessage.new(amount: 100)

# This works
PaymentMessage.new(payment_id: 'PAY-123', amount: 100)
```

### 3. Property Transformation

Transform property values when they're set:

```ruby
class UserMessage < SmartMessage::Base
  property :email, transform_with: ->(v) { v.to_s.downcase }
  property :name, transform_with: ->(v) { v.to_s.strip.capitalize }
  property :tags, transform_with: ->(v) { Array(v).map(&:to_s) }
end

user = UserMessage.new(
  email: 'USER@EXAMPLE.COM',
  name: '  john  ',
  tags: 'admin'
)

user.email # => 'user@example.com'
user.name  # => 'John'
user.tags  # => ['admin']
```

### 4. Property Translation (from Hashie::Extensions::Dash::PropertyTranslation)

Map external field names to internal property names:

```ruby
class ApiMessage < SmartMessage::Base
  property :user_id, from: :userId
  property :order_date, from: 'orderDate'
  property :total_amount, from: [:totalAmount, :total, :amount]
end

# All of these work
msg1 = ApiMessage.new(userId: 123)
msg2 = ApiMessage.new(user_id: 123)
msg3 = ApiMessage.new('orderDate' => '2024-01-01')
msg4 = ApiMessage.new(totalAmount: 100)  # or total: 100, or amount: 100

msg1.user_id # => 123
```

### 5. Type Coercion (from Hashie::Extensions::Coercion)

Automatically coerce property values to specific types:

```ruby
class TypedMessage < SmartMessage::Base
  property :count
  property :price
  property :active
  property :tags
  property :metadata

  coerce_key :count, Integer
  coerce_key :price, Float
  coerce_key :active, ->(v) { v.to_s.downcase == 'true' }
  coerce_key :tags, Array[String]
  coerce_key :metadata, Hash
end

msg = TypedMessage.new(
  count: '42',
  price: '19.99',
  active: 'yes',
  tags: 'important',
  metadata: nil
)

msg.count    # => 42 (Integer)
msg.price    # => 19.99 (Float)
msg.active   # => false (Boolean logic)
msg.tags     # => ['important'] (Array)
msg.metadata # => {} (Hash)
```

### 6. Property Descriptions (SmartMessage Enhancement)

Add human-readable descriptions to document your properties for dynamic LLM integration:

```ruby
class DocumentedMessage < SmartMessage::Base
  property :transaction_id,
           required: true,
           description: "Unique identifier for the transaction"

  property :amount,
           transform_with: ->(v) { BigDecimal(v.to_s) },
           description: "Transaction amount in the smallest currency unit"

  property :currency,
           default: 'USD',
           description: "ISO 4217 currency code"

  property :status,
           default: 'pending',
           description: "Current transaction status: pending, completed, failed"

  property :metadata,
           default: {},
           description: "Additional transaction metadata as key-value pairs"
end

# Access descriptions programmatically
DocumentedMessage.property_description(:amount)
# => "Transaction amount in the smallest currency unit"

DocumentedMessage.property_descriptions
# => {
#      transaction_id: "Unique identifier for the transaction",
#      amount: "Transaction amount in the smallest currency unit",
#      currency: "ISO 4217 currency code",
#      status: "Current transaction status: pending, completed, failed",
#      metadata: "Additional transaction metadata as key-value pairs"
#    }

DocumentedMessage.described_properties
# => [:transaction_id, :amount, :currency, :status, :metadata]
```

## Accessing Property Information

SmartMessage provides several methods to introspect properties:

```ruby
class IntrospectionExample < SmartMessage::Base
  property :id, required: true, description: "Unique identifier"
  property :name, description: "Display name"
  property :created_at, default: -> { Time.now }
  property :tags
end

# Instance methods
instance = IntrospectionExample.new(id: 1, name: "Test")
instance.fields  # => Set[:id, :name, :created_at, :tags]
instance.to_h    # => Hash of all properties and values

# Class methods
IntrospectionExample.fields              # => Set[:id, :name, :created_at, :tags]
IntrospectionExample.property_descriptions  # => Hash of descriptions
IntrospectionExample.described_properties   # => [:id, :name]
```

## Hashie Extensions

SmartMessage::Base automatically includes these Hashie extensions:

### 1. DeepMerge
Allows deep merging of nested hash properties:

```ruby
msg = MyMessage.new(config: { a: 1, b: { c: 2 } })
msg.deep_merge(config: { b: { d: 3 } })
# => config: { a: 1, b: { c: 2, d: 3 } }
```

### 2. IgnoreUndeclared
Silently ignores properties that haven't been declared:

```ruby
# Won't raise an error for unknown properties
msg = MyMessage.new(known: 'value', unknown: 'ignored')
```

### 3. IndifferentAccess
Access properties with strings or symbols:

```ruby
msg = MyMessage.new('name' => 'John')
msg[:name]    # => 'John'
msg['name']   # => 'John'
msg.name      # => 'John'
```

### 4. MethodAccess
Access properties as methods:

```ruby
msg = MyMessage.new(name: 'John')
msg.name         # => 'John'
msg.name = 'Jane'
msg.name         # => 'Jane'
```

### 5. MergeInitializer
Allows initializing with merged hash values:

```ruby
defaults = { status: 'active', retries: 3 }
msg = MyMessage.new(defaults.merge(status: 'pending'))
# => status: 'pending', retries: 3
```

## Examples

### Complete Example: Order Processing Message

```ruby
class OrderProcessingMessage < SmartMessage::Base
  # Required fields with descriptions
  property :order_id,
           required: true,
           description: "Unique order identifier from the ordering system"

  property :customer_id,
           required: true,
           description: "Customer who placed the order"

  # Amount with transformation and description
  property :total_amount,
           transform_with: ->(v) { BigDecimal(v.to_s) },
           description: "Total order amount including tax and shipping"

  # Status with default and validation description
  property :status,
           default: 'pending',
           description: "Order status: pending, processing, shipped, delivered, cancelled"

  # Items with coercion
  property :items,
           default: [],
           description: "Array of order line items"

  # Timestamps with dynamic defaults
  property :created_at,
           default: -> { Time.now },
           description: "When the order was created"

  property :updated_at,
           default: -> { Time.now },
           description: "Last modification timestamp"

  # Optional fields
  property :notes,
           description: "Optional order notes or special instructions"

  property :shipping_address,
           description: "Shipping address as a nested hash"

  # Field translation for external APIs
  property :external_ref,
           from: [:externalReference, :ext_ref],
           description: "Reference ID from external system"
end

# Usage
order = OrderProcessingMessage.new(
  order_id: 'ORD-2024-001',
  customer_id: 'CUST-123',
  total_amount: '149.99',
  items: [
    { sku: 'WIDGET-A', quantity: 2, price: 49.99 },
    { sku: 'WIDGET-B', quantity: 1, price: 50.01 }
  ],
  shipping_address: {
    street: '123 Main St',
    city: 'Springfield',
    state: 'IL',
    zip: '62701'
  },
  externalReference: 'EXT-789'  # Note: uses translated field name
)

# Access properties
order.order_id         # => 'ORD-2024-001'
order.total_amount     # => BigDecimal('149.99')
order.status           # => 'pending' (default)
order.external_ref     # => 'EXT-789' (translated)
order.created_at       # => Time object

# Get property information
OrderProcessingMessage.property_description(:total_amount)
# => "Total order amount including tax and shipping"

OrderProcessingMessage.property_descriptions.keys
# => [:order_id, :customer_id, :total_amount, :status, :items, ...]
```

### Example: API Integration Message

```ruby
class ApiWebhookMessage < SmartMessage::Base
  # Handle different API naming conventions
  property :event_type,
           from: [:eventType, :event, :type],
           required: true,
           description: "Type of webhook event"

  property :payload,
           required: true,
           description: "Event payload data"

  property :timestamp,
           from: [:timestamp, :created_at, :occurredAt],
           transform_with: ->(v) { Time.parse(v.to_s) },
           description: "When the event occurred"

  property :retry_count,
           from: :retryCount,
           default: 0,
           transform_with: ->(v) { v.to_i },
           description: "Number of delivery attempts"

  property :signature,
           description: "HMAC signature for webhook validation"
end

# Can initialize with various field names
webhook1 = ApiWebhookMessage.new(
  eventType: 'order.completed',
  payload: { order_id: 123 },
  occurredAt: '2024-01-01T10:00:00Z',
  retryCount: '2'
)

webhook2 = ApiWebhookMessage.new(
  type: 'order.completed',        # Alternative field name
  payload: { order_id: 123 },
  timestamp: Time.now,             # Alternative field name
  retry_count: 2                   # Internal field name
)
```

## Best Practices

1. **Always add descriptions** to document the purpose and format of each property
2. **Use required properties** for fields that must be present for valid messages
3. **Provide sensible defaults** for optional fields to reduce boilerplate
4. **Use transformations** to ensure data consistency and type safety
5. **Leverage field translation** when integrating with external APIs that use different naming conventions
6. **Document valid values** in descriptions for enum-like fields (e.g., status fields)
7. **Use type coercion** for fields that may come from untrusted sources (like HTTP parameters)

## Property Option Compatibility

Multiple options can be combined on a single property:

```ruby
property :amount,
         required: true,
         from: [:amount, :total, :value],
         transform_with: ->(v) { BigDecimal(v.to_s) },
         description: "Transaction amount in cents"
```

The processing order is:
1. Field translation (from)
2. Default value (if not provided)
3. Required validation
4. Type coercion
5. Transformation
6. Value assignment

## Limitations

- Property names must be valid Ruby method names
- The `_sm_` prefix is reserved for internal SmartMessage properties
- Descriptions are metadata only and don't affect runtime behavior
- Some Hashie options may conflict if used incorrectly (e.g., required with default)
