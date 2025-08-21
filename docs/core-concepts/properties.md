# SmartMessage Property System

The SmartMessage property system builds on Hashie::Dash to provide a robust, declarative way to define message attributes. This document covers all available property options and features.

## Table of Contents
- [Basic Property Definition](#basic-property-definition)
- [Schema Versioning](#schema-versioning)
- [Class-Level Description](#class-level-description)
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

## Schema Versioning

SmartMessage supports schema versioning to enable message evolution while maintaining compatibility:

```ruby
class OrderMessage < SmartMessage::Base
  version 2  # Declare schema version
  
  property :order_id, required: true
  property :customer_email  # Added in version 2
end
```

### Version Management

```ruby
# Version 1 message
class V1OrderMessage < SmartMessage::Base
  version 1  # or omit for default version 1
  
  property :order_id, required: true
  property :amount, required: true
end

# Version 2 message with additional field
class V2OrderMessage < SmartMessage::Base
  version 2
  
  property :order_id, required: true
  property :amount, required: true
  property :customer_email  # New in version 2
end

# Version 3 message with validation
class V3OrderMessage < SmartMessage::Base
  version 3
  
  property :order_id, 
    required: true,
    validate: ->(v) { v.is_a?(String) && v.length > 0 }
    
  property :amount, 
    required: true,
    validate: ->(v) { v.is_a?(Numeric) && v > 0 }
    
  property :customer_email,
    validate: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
end
```

### Version Validation

The framework automatically validates version compatibility:

```ruby
message = V2OrderMessage.new(order_id: "123", amount: 99.99)
# Header automatically gets version: 2

# Version validation happens automatically
message.validate!  # Validates message + header + version compatibility

# Manual version validation
message.validate_header_version!  # Checks header version matches class version

# Check version information
V2OrderMessage.version                    # => 2
V2OrderMessage.expected_header_version    # => 2
message._sm_header.version               # => 2
```

### Version Evolution Patterns

```ruby
# Pattern 1: Additive changes (safe)
class UserMessageV1 < SmartMessage::Base
  version 1
  property :user_id, required: true
  property :name, required: true
end

class UserMessageV2 < SmartMessage::Base
  version 2
  property :user_id, required: true
  property :name, required: true
  property :email  # Optional addition - backward compatible
end

# Pattern 2: Field validation evolution
class ProductMessageV1 < SmartMessage::Base
  version 1
  property :product_id, required: true
  property :price, required: true
end

class ProductMessageV2 < SmartMessage::Base
  version 2
  property :product_id, 
    required: true,
    validate: ->(v) { v.is_a?(String) && v.match?(/\APROD-\d+\z/) }
    
  property :price, 
    required: true,
    validate: ->(v) { v.is_a?(Numeric) && v > 0 }
end
```

## Class-Level Description

In addition to property-level descriptions, you can add a description for the entire message class using the `description` DSL method:

```ruby
class OrderMessage < SmartMessage::Base
  description "Handles order processing and fulfillment workflow"
  
  property :order_id, description: "Unique order identifier"
  property :amount, description: "Total amount in cents"
end

# Access the class description
OrderMessage.description  # => "Handles order processing and fulfillment workflow"

# Instance access to class description
order = OrderMessage.new(order_id: "123", amount: 9999)
order.description  # => "Handles order processing and fulfillment workflow"
```

### Setting Descriptions

Class descriptions can be set in multiple ways:

```ruby
# 1. During class definition
class PaymentMessage < SmartMessage::Base
  description "Processes payment transactions"
  property :payment_id
end

# 2. After class definition
class RefundMessage < SmartMessage::Base
  property :refund_id
end
RefundMessage.description "Handles payment refunds and reversals"

# 3. Within config block
class NotificationMessage < SmartMessage::Base
  config do
    description "Sends notifications to users"
    transport MyTransport.new
    serializer MySerializer.new
  end
end
```

### Default Descriptions

Classes without explicit descriptions automatically receive a default description:

```ruby
class MyMessage < SmartMessage::Base
  property :data
end

MyMessage.description  # => "MyMessage is a SmartMessage"

# This applies to all unnamed message classes
class SomeModule::ComplexMessage < SmartMessage::Base
  property :info
end

SomeModule::ComplexMessage.description  
# => "SomeModule::ComplexMessage is a SmartMessage"
```

### Use Cases

Class descriptions are useful for:
- Documenting the overall purpose of a message class
- Providing context for code generation tools
- Integration with documentation systems
- API documentation generation
- Dynamic message introspection in gateway applications

### Important Notes

- Class descriptions are not inherited by subclasses - each class maintains its own description
- Setting a description to `nil` will revert to the default description
- Descriptions are stored as strings and can include multiline content
- Both class and instance methods are available to access descriptions

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

### 6. Property Validation (SmartMessage Enhancement)

Add custom validation logic to ensure data integrity:

```ruby
class ValidatedMessage < SmartMessage::Base
  # Lambda validation
  property :age,
           validate: ->(v) { v.is_a?(Integer) && v.between?(1, 120) },
           validation_message: "Age must be an integer between 1 and 120"

  # Regex validation for email
  property :email,
           validate: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
           validation_message: "Must be a valid email address"

  # Array inclusion validation
  property :status,
           validate: ['active', 'inactive', 'pending'],
           validation_message: "Status must be active, inactive, or pending"

  # Range validation
  property :score,
           validate: (0..100),
           validation_message: "Score must be between 0 and 100"

  # Class type validation
  property :created_at,
           validate: Time,
           validation_message: "Must be a Time object"

  # Symbol method validation
  property :username,
           validate: :valid_username?,
           validation_message: "Username contains invalid characters"

  private

  def valid_username?(value)
    value.to_s.match?(/\A[a-zA-Z0-9_]+\z/)
  end
end

# Validation usage
message = ValidatedMessage.new(age: 25, email: "test@example.com")

# Validate entire message
message.validate!           # Raises SmartMessage::Errors::ValidationError on failure
message.valid?              # Returns true/false

# Get validation errors
errors = message.validation_errors
errors.each do |error|
  puts "#{error[:property]}: #{error[:message]}"
end
```

### 7. Property Descriptions (SmartMessage Enhancement)

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
  description "Manages the complete order lifecycle from placement to delivery"
  
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

# Get class and property information
OrderProcessingMessage.description
# => "Manages the complete order lifecycle from placement to delivery"

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
