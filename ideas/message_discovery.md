## Message Discovery & Dynamic Class Creation

### Overview

SmartMessage can automatically discover and catalog message types across distributed systems, enabling:

- **Service discovery** - Find available message types from other services
- **Dynamic class creation** - Create message classes from stored schemas at runtime
- **Cross-service communication** - Connect to new services without code changes
- **API documentation** - Generate docs from actual schemas in use

### Service Discovery Implementation

```ruby
module SmartMessage
  class SchemaRegistry
    # Service discovery: find available message types
    def discover_message_classes(environment: nil, service: nil)
      filters = ["status = 'active'"]
      params = []

      if environment
        filters << "deployment_environment = $#{params.length + 1}"
        params << environment
      end

      if service
        filters << "registered_by = $#{params.length + 1}"
        params << service
      end

      connection_pool.with do |conn|
        conn.execute(<<~SQL, params)
          SELECT DISTINCT
            class_name,
            MAX(class_version) as latest_version,
            MAX(class_description) as description,
            COUNT(*) as version_count,
            MAX(registered_at) as last_updated
          FROM smart_message_schemas
          WHERE #{filters.join(' AND ')}
          GROUP BY class_name
          ORDER BY class_name
        SQL
      end
    end
  end
end
```

### Dynamic Class Creation

```ruby
module SmartMessage
  class SchemaRegistry
    # Dynamic class creation from stored schema
    def create_class_from_schema(class_name, version = :latest, namespace = Object)
      schema = fetch_schema(class_name, version)
      raise ArgumentError, "Schema not found: #{class_name} v#{version}" unless schema

      # Extract class name without namespace
      simple_class_name = class_name.split('::').last

      # Create dynamic class
      dynamic_class = Class.new(SmartMessage::Base) do
        # Set metadata
        description schema['class_description']
        version schema['class_version']

        # Add properties with full validation
        schema['properties_schema'].each do |prop|
          property_options = build_property_options(prop)
          property prop['name'].to_sym, **property_options
        end

        # Apply validations
        apply_validation_rules(schema['validations_schema']) if schema['validations_schema']

        # Apply configuration
        apply_configuration(schema['configuration_schema']) if schema['configuration_schema']

        # Mark as dynamically created
        define_singleton_method(:dynamically_created?) { true }
        define_singleton_method(:source_schema) { schema }
      end

      # Set constant
      namespace.const_set(simple_class_name, dynamic_class)
      dynamic_class
    end

    private

    def fetch_schema(class_name, version)
      version_clause = version == :latest ?
        "ORDER BY class_version DESC LIMIT 1" :
        "AND class_version = #{version.to_i}"

      connection_pool.with do |conn|
        conn.execute(<<~SQL, [class_name]).first
          SELECT * FROM smart_message_schemas
          WHERE class_name = $1 AND status = 'active'
          #{version_clause}
        SQL
      end
    end
  end
end
```

### Usage Examples

#### Service Discovery
```ruby
# Discover all available message types in production
available_messages = SmartMessage::SchemaRegistry.discover_message_classes(
  environment: 'production'
)

available_messages.each do |msg|
  puts "#{msg['class_name']} v#{msg['latest_version']} - #{msg['description']}"
end

# Discover messages from a specific service
partner_messages = SmartMessage::SchemaRegistry.discover_message_classes(
  service: 'payment-service'
)
```

#### Dynamic Class Creation
```ruby
# Create a message class dynamically from another service's schema
PaymentMessage = SmartMessage::SchemaRegistry.create_class_from_schema(
  'PaymentMessage',
  version: :latest
)

# Use the dynamically created class
payment = PaymentMessage.new(
  amount: 99.99,
  currency: 'USD',
  customer_id: 'cust_123'
)

# Check if class was dynamically created
payment.class.dynamically_created? # => true
payment.class.source_schema # => returns original schema used to create class
```

#### Cross-Service Communication
```ruby
# Load message schemas from partner service
partner_schemas = SmartMessage::SchemaRegistry.discover_message_classes(
  service: 'partner-payment-service'
)

# Automatically create local classes for their message types
partner_schemas.each do |schema_info|
  SmartMessage::SchemaRegistry.create_class_from_schema(
    schema_info['class_name'],
    namespace: PartnerMessages
  )
end

# Now can subscribe to partner messages
PartnerMessages::PaymentCompletedMessage.subscribe do |message|
  # Handle partner payment notifications
end
```

### Discovery Benefits

1. **Automatic Service Discovery**: Find available message types across services without manual documentation
2. **Dynamic Integration**: Connect to new services without code changes or deployments
3. **API Documentation**: Generate accurate docs from actual schemas in use
4. **Validation**: Ensure message compatibility across service boundaries
5. **Debugging**: Understand message structure across the entire system
6. **Zero-downtime Updates**: Services can discover and adapt to new message types at runtime