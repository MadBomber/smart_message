## Message Schema Registry

### Overview

SmartMessage can automatically register and track message schemas, enabling:

- **Automatic schema registration** when message classes are defined
- **Schema evolution tracking** across versions and deployments  
- **Schema storage** in a centralized database for persistence
- **Schema versioning** to track changes over time
- **Compliance tracking** for audit requirements

### Database Schema for Message Registry

```sql
CREATE TABLE smart_message_schemas (
  id BIGSERIAL PRIMARY KEY,

  -- Class identification
  class_name VARCHAR NOT NULL,
  class_version INTEGER NOT NULL DEFAULT 1,
  class_description TEXT,

  -- Complete schema storage
  schema_definition JSONB NOT NULL,  -- Full serialized class definition
  properties_schema JSONB NOT NULL,  -- Properties for quick access/filtering
  validations_schema JSONB,          -- Validation rules and constraints
  configuration_schema JSONB,        -- Transport/serializer configs

  -- Registration metadata
  registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  registered_by VARCHAR NOT NULL,    -- Service/application identifier
  deployment_environment VARCHAR DEFAULT 'unknown', -- dev/staging/prod
  ruby_version VARCHAR,
  framework_version VARCHAR,

  -- Schema evolution tracking
  parent_schema_id BIGINT REFERENCES smart_message_schemas(id),
  schema_hash VARCHAR(64) NOT NULL,  -- SHA256 of schema for change detection
  schema_fingerprint VARCHAR(32),    -- Short hash for quick comparison

  -- Lifecycle management
  status VARCHAR DEFAULT 'active' CHECK (status IN ('active', 'deprecated', 'archived')),
  deprecated_at TIMESTAMP WITH TIME ZONE,
  archived_at TIMESTAMP WITH TIME ZONE,

  -- Performance constraints
  UNIQUE(class_name, class_version, registered_by),
  INDEX idx_schema_discovery (class_name, status, registered_by),
  INDEX idx_schema_evolution (parent_schema_id, registered_at),
  INDEX idx_schema_fingerprint (schema_fingerprint),
  INDEX idx_active_schemas (status, registered_at DESC) WHERE status = 'active'
);
```

### Automatic Schema Registration

```ruby
# Enhanced SmartMessage::Base with automatic schema registration
class Base < Hashie::Dash
  # Hook that fires when any class inherits from SmartMessage::Base
  def self.inherited(subclass)
    super(subclass)

    # Set up deferred registration after class is fully loaded
    subclass.define_singleton_method(:method_added) do |method_name|
      # Trigger registration after class is complete
      if method_name == :initialize && !@schema_registered
        @schema_registered = true
        register_schema_async
      end
    end
  end

  # Extract complete class schema for serialization
  def self.serialize_schema
    {
      class_name: name,
      class_version: version || 1,
      class_description: description,
      properties_schema: extract_properties_schema,
      validations_schema: extract_validations_schema,
      configuration_schema: extract_configuration_schema,

      # Metadata
      created_at: Time.current.iso8601,
      ruby_version: RUBY_VERSION,
      framework_version: SmartMessage::VERSION,

      # Schema fingerprinting
      schema_hash: calculate_schema_hash
    }
  end

  private

  def self.register_schema_async
    # Non-blocking registration to avoid slowing class loading
    Thread.new do
      begin
        SmartMessage::SchemaRegistry.register(self)
        logger.debug "[SmartMessage] Registered schema: #{name} v#{version || 1}"
      rescue => e
        logger.warn "[SmartMessage] Failed to register schema for #{name}: #{e.message}"
      end
    end
  end

  def self.extract_properties_schema
    return [] unless respond_to?(:properties)

    properties.map do |name, opts|
      {
        name: name.to_s,
        type: opts[:type]&.name || infer_property_type(name),
        required: opts[:required] || false,
        default: opts[:default],
        description: property_description(name),
        validation_rule: extract_property_validation(name),
        constraints: extract_property_constraints(name)
      }
    end
  end

  def self.extract_configuration_schema
    {
      transport: transport.class.name,
      serializer: serializer.class.name,
      logger: logger.class.name,
      plugins: extract_plugin_configuration
    }
  rescue
    {}
  end

  def self.calculate_schema_hash
    schema_content = {
      name: name,
      version: version || 1,
      properties: properties&.keys&.sort,
      validations: extract_validation_keys
    }
    Digest::SHA256.hexdigest(schema_content.to_json)
  end
end
```

### Schema Registry Implementation

```ruby
module SmartMessage
  class SchemaRegistry
    extend self

    def register(message_class)
      return unless database_available?

      schema = message_class.serialize_schema

      connection_pool.with do |conn|
        # Check if schema already exists with same hash
        existing = conn.execute(<<~SQL, [schema[:class_name], schema[:schema_hash]]).first
          SELECT id FROM smart_message_schemas
          WHERE class_name = $1 AND schema_hash = $2 AND status = 'active'
        SQL

        return if existing # Schema already registered

        # Find parent schema (previous version)
        parent = find_parent_schema(schema[:class_name], schema[:class_version])

        # Insert new schema
        conn.execute(<<~SQL, schema_insert_params(schema, parent))
          INSERT INTO smart_message_schemas (
            class_name, class_version, class_description, schema_definition,
            properties_schema, validations_schema, configuration_schema,
            registered_by, deployment_environment, ruby_version, framework_version,
            parent_schema_id, schema_hash, schema_fingerprint
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
        SQL
      end
    end

    # Schema evolution: compare versions
    def schema_evolution(class_name)
      connection_pool.with do |conn|
        conn.execute(<<~SQL, [class_name])
          WITH RECURSIVE evolution AS (
            -- Start with latest version
            SELECT id, class_name, class_version, parent_schema_id,
                   schema_hash, registered_at, 0 as depth
            FROM smart_message_schemas
            WHERE class_name = $1 AND status = 'active'
            ORDER BY class_version DESC LIMIT 1

            UNION ALL

            -- Follow parent chain
            SELECT s.id, s.class_name, s.class_version, s.parent_schema_id,
                   s.schema_hash, s.registered_at, e.depth + 1
            FROM smart_message_schemas s
            JOIN evolution e ON s.id = e.parent_schema_id
          )
          SELECT * FROM evolution ORDER BY depth ASC;
        SQL
      end
    end

    private

    def database_available?
      defined?(SmartMessage::Transport::DatabaseTransport) &&
        SmartMessage.configuration.schema_registry_enabled?
    end

    def connection_pool
      @connection_pool ||= SmartMessage::Transport::DatabaseTransport.default.connection_pool
    end

    def find_parent_schema(class_name, class_version)
      return nil if class_version <= 1
      
      connection_pool.with do |conn|
        conn.execute(<<~SQL, [class_name, class_version - 1]).first
          SELECT id FROM smart_message_schemas
          WHERE class_name = $1 AND class_version = $2 AND status = 'active'
          ORDER BY registered_at DESC LIMIT 1
        SQL
      end
    end

    def schema_insert_params(schema, parent)
      [
        schema[:class_name],
        schema[:class_version],
        schema[:class_description],
        schema.to_json,
        schema[:properties_schema].to_json,
        schema[:validations_schema]&.to_json,
        schema[:configuration_schema]&.to_json,
        SmartMessage.configuration.service_name || 'unknown',
        SmartMessage.configuration.environment || 'unknown',
        schema[:ruby_version],
        schema[:framework_version],
        parent&.fetch('id'),
        schema[:schema_hash],
        schema[:schema_hash][0..7]  # First 8 chars as fingerprint
      ]
    end
  end
end
```

### Schema Evolution Tracking

```ruby
# See how OrderMessage has evolved over time
evolution = SmartMessage::SchemaRegistry.schema_evolution('OrderMessage')

evolution.each do |version_info|
  puts "Version #{version_info['class_version']}: #{version_info['registered_at']}"
  puts "  Hash: #{version_info['schema_hash'][0..7]}..."
  puts "  Parent: #{version_info['parent_schema_id']}"
end

# Compare schemas between versions
def compare_schemas(class_name, version1, version2)
  schema1 = fetch_schema(class_name, version1)
  schema2 = fetch_schema(class_name, version2)
  
  {
    properties_added: schema2['properties'] - schema1['properties'],
    properties_removed: schema1['properties'] - schema2['properties'],
    validations_changed: schema1['validations'] != schema2['validations']
  }
end
```

### JSON Schema Representation

SmartMessage classes can be represented as standard JSON Schema documents, providing interoperability with other systems and languages.

```ruby
class Base < Hashie::Dash
  def self.to_json_schema
    {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "$id" => "https://smartmessage.io/schemas/#{name.underscore}/v#{version || 1}",
      
      "title" => name,
      "description" => description || "#{name} message class",
      "type" => "object",
      "version" => version || 1,
      
      # Message metadata
      "x-smart-message" => {
        "class_name" => name,
        "version" => version || 1,
        "transport" => transport&.class&.name,
        "serializer" => serializer&.class&.name,
        "registered_at" => Time.current.iso8601,
        "ruby_version" => RUBY_VERSION,
        "framework_version" => SmartMessage::VERSION
      },
      
      # Properties with descriptions and validations
      "properties" => properties_to_json_schema,
      "required" => extract_required_properties,
      "additionalProperties" => false
    }
  end

  private

  def self.properties_to_json_schema
    return {} unless respond_to?(:properties)
    
    schema_props = {}
    
    properties.each do |name, opts|
      prop_schema = {
        "description" => property_description(name) || "Property: #{name}"
      }
      
      # Infer JSON Schema type from Ruby type
      if opts[:type]
        prop_schema["type"] = ruby_to_json_type(opts[:type])
      end
      
      # Add validation constraints
      if validation = property_validation(name)
        case validation
        when Regexp
          prop_schema["pattern"] = validation.source
        when Range
          prop_schema["minimum"] = validation.min if validation.min
          prop_schema["maximum"] = validation.max if validation.max
        when Array
          prop_schema["enum"] = validation
        when Proc, Method
          prop_schema["x-custom-validation"] = validation.source_location.join(":")
        end
      end
      
      # Add default value if present
      if opts[:default]
        prop_schema["default"] = opts[:default]
      end
      
      # Add format hints for common patterns
      if name.to_s.include?("email")
        prop_schema["format"] = "email"
      elsif name.to_s.include?("date")
        prop_schema["format"] = "date-time"
      elsif name.to_s.include?("url") || name.to_s.include?("uri")
        prop_schema["format"] = "uri"
      end
      
      schema_props[name.to_s] = prop_schema
    end
    
    # Add SmartMessage header as a property
    schema_props["_sm_header"] = {
      "type" => "object",
      "description" => "SmartMessage routing and metadata header",
      "properties" => {
        "uuid" => {"type" => "string", "format" => "uuid"},
        "from" => {"type" => "string", "description" => "Message sender identifier"},
        "to" => {"type" => ["string", "null"], "description" => "Message recipient identifier"},
        "version" => {"type" => "integer", "description" => "Schema version"},
        "published_at" => {"type" => "string", "format" => "date-time"},
        "message_class" => {"type" => "string"},
        "thread_id" => {"type" => ["string", "null"]},
        "correlation_id" => {"type" => ["string", "null"]}
      }
    }
    
    schema_props
  end
  
  def self.ruby_to_json_type(ruby_type)
    case ruby_type.name
    when "String" then "string"
    when "Integer", "Fixnum", "Bignum" then "integer"
    when "Float", "BigDecimal" then "number"
    when "TrueClass", "FalseClass", "Boolean" then "boolean"
    when "Array" then "array"
    when "Hash" then "object"
    when "NilClass" then "null"
    else "string" # Default fallback
    end
  end
  
  def self.extract_required_properties
    return [] unless respond_to?(:properties)
    
    properties.select { |_, opts| opts[:required] }.keys.map(&:to_s)
  end
end
```

#### Example: OrderMessage as JSON Schema

```ruby
class OrderMessage < SmartMessage::Base
  version 2
  description "Represents a customer order in the e-commerce system"
  
  property :order_id, 
    required: true,
    description: "Unique identifier for the order"
    
  property :customer_email,
    required: true,
    validate: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
    description: "Customer's email address for order notifications"
    
  property :amount,
    required: true,
    type: Float,
    validate: ->(v) { v > 0 },
    description: "Total order amount in the specified currency"
    
  property :currency,
    default: "USD",
    validate: ["USD", "EUR", "GBP", "CAD"],
    description: "ISO 4217 currency code"
    
  property :items,
    type: Array,
    description: "List of items in the order"
    
  property :created_at,
    type: Time,
    description: "Timestamp when the order was created"
end

# Generate JSON Schema
puts JSON.pretty_generate(OrderMessage.to_json_schema)
```

Output:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://smartmessage.io/schemas/order_message/v2",
  "title": "OrderMessage",
  "description": "Represents a customer order in the e-commerce system",
  "type": "object",
  "version": 2,
  "x-smart-message": {
    "class_name": "OrderMessage",
    "version": 2,
    "transport": "SmartMessage::Transport::RabbitMQ",
    "serializer": "SmartMessage::Serializer::JSON",
    "registered_at": "2024-01-15T10:30:00Z",
    "ruby_version": "3.2.0",
    "framework_version": "1.0.0"
  },
  "properties": {
    "order_id": {
      "description": "Unique identifier for the order",
      "type": "string"
    },
    "customer_email": {
      "description": "Customer's email address for order notifications",
      "type": "string",
      "format": "email",
      "pattern": "[\\w+\\-.]+@[a-z\\d\\-]+(\\.[a-z\\d\\-]+)*\\.[a-z]+"
    },
    "amount": {
      "description": "Total order amount in the specified currency",
      "type": "number",
      "x-custom-validation": "order_message.rb:15"
    },
    "currency": {
      "description": "ISO 4217 currency code",
      "type": "string",
      "default": "USD",
      "enum": ["USD", "EUR", "GBP", "CAD"]
    },
    "items": {
      "description": "List of items in the order",
      "type": "array"
    },
    "created_at": {
      "description": "Timestamp when the order was created",
      "type": "string",
      "format": "date-time"
    },
    "_sm_header": {
      "type": "object",
      "description": "SmartMessage routing and metadata header",
      "properties": {
        "uuid": {"type": "string", "format": "uuid"},
        "from": {"type": "string", "description": "Message sender identifier"},
        "to": {"type": ["string", "null"], "description": "Message recipient identifier"},
        "version": {"type": "integer", "description": "Schema version"},
        "published_at": {"type": "string", "format": "date-time"},
        "message_class": {"type": "string"},
        "thread_id": {"type": ["string", "null"]},
        "correlation_id": {"type": ["string", "null"]}
      }
    }
  },
  "required": ["order_id", "customer_email", "amount"],
  "additionalProperties": false
}
```

### JSON Schema Integration Benefits

1. **Standard Compliance**: Uses JSON Schema draft 2020-12 for maximum compatibility
2. **Rich Descriptions**: Both message-level and property-level descriptions included
3. **Validation Portability**: Validation rules translated to JSON Schema constraints
4. **Type Safety**: Ruby types mapped to JSON Schema types with format hints
5. **API Documentation**: Can generate OpenAPI/AsyncAPI specs from schemas
6. **Cross-Language Support**: Other languages can validate messages using the schema
7. **Tooling Integration**: Works with JSON Schema validators and code generators

### Dynamic Class Reconstruction from JSON Schema

SmartMessage can dynamically rebuild Ruby classes from stored JSON Schemas, enabling complete round-trip conversion:

```ruby
module SmartMessage
  class SchemaRegistry
    # Create a Ruby class from a JSON Schema stored in database
    def self.from_json_schema(json_schema, namespace = Object)
      schema = json_schema.is_a?(String) ? JSON.parse(json_schema) : json_schema
      
      # Extract class name from schema
      class_name = schema.dig("x-smart-message", "class_name") || 
                   schema["title"] || 
                   raise(ArgumentError, "No class name found in schema")
      
      simple_class_name = class_name.split('::').last
      
      # Create new class inheriting from SmartMessage::Base
      dynamic_class = Class.new(SmartMessage::Base) do
        # Set class metadata
        version schema.dig("x-smart-message", "version") || schema["version"]
        description schema["description"] if schema["description"]
        
        # Configure plugins if specified
        if transport_name = schema.dig("x-smart-message", "transport")
          transport transport_name.constantize.new rescue nil
        end
        
        if serializer_name = schema.dig("x-smart-message", "serializer")
          serializer serializer_name.constantize.new rescue nil
        end
        
        # Process properties from JSON Schema
        if properties = schema["properties"]
          required_fields = schema["required"] || []
          
          properties.each do |prop_name, prop_schema|
            # Skip the header property
            next if prop_name == "_sm_header"
            
            # Build property options
            prop_options = {}
            
            # Set required flag
            prop_options[:required] = true if required_fields.include?(prop_name)
            
            # Set Ruby type from JSON Schema type
            if json_type = prop_schema["type"]
              prop_options[:type] = json_to_ruby_type(json_type)
            end
            
            # Set default value
            if prop_schema.key?("default")
              prop_options[:default] = prop_schema["default"]
            end
            
            # Set description
            prop_options[:description] = prop_schema["description"] if prop_schema["description"]
            
            # Set validation from JSON Schema constraints
            validation = extract_validation_from_json_schema(prop_schema)
            prop_options[:validate] = validation if validation
            
            # Set validation message if custom validation exists
            if prop_schema["x-custom-validation"]
              prop_options[:validation_message] = "Value failed custom validation"
            end
            
            # Define the property
            property prop_name.to_sym, **prop_options
          end
        end
        
        # Mark as dynamically created from JSON Schema
        define_singleton_method(:dynamically_created?) { true }
        define_singleton_method(:source_json_schema) { schema }
        
        # Override to_json_schema to return the original
        define_singleton_method(:to_json_schema) { schema }
      end
      
      # Set the class constant in the namespace
      namespace.const_set(simple_class_name, dynamic_class)
      dynamic_class
    end
    
    private
    
    def self.json_to_ruby_type(json_type)
      type_map = {
        "string" => String,
        "integer" => Integer,
        "number" => Float,
        "boolean" => TrueClass,
        "array" => Array,
        "object" => Hash,
        "null" => NilClass
      }
      
      # Handle array of types (e.g., ["string", "null"])
      if json_type.is_a?(Array)
        # Find first non-null type
        non_null_type = json_type.find { |t| t != "null" }
        type_map[non_null_type] || String
      else
        type_map[json_type] || String
      end
    end
    
    def self.extract_validation_from_json_schema(prop_schema)
      # Enum validation
      if enum_values = prop_schema["enum"]
        return enum_values
      end
      
      # Pattern validation
      if pattern = prop_schema["pattern"]
        return Regexp.new(pattern)
      end
      
      # Range validation for numbers
      if prop_schema["minimum"] || prop_schema["maximum"]
        min = prop_schema["minimum"] || -Float::INFINITY
        max = prop_schema["maximum"] || Float::INFINITY
        return (min..max)
      end
      
      # Format-based validation
      case prop_schema["format"]
      when "email"
        return /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
      when "uri", "url"
        return /\A#{URI::regexp}\z/
      when "uuid"
        return /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
      end
      
      nil
    end
  end
end
```

### Round-Trip Example

```ruby
# Original message class
class OrderMessage < SmartMessage::Base
  version 2
  description "Represents a customer order in the e-commerce system"
  
  property :order_id, 
    required: true,
    description: "Unique identifier for the order"
    
  property :customer_email,
    required: true,
    validate: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
    description: "Customer's email address for order notifications"
    
  property :amount,
    required: true,
    type: Float,
    description: "Total order amount in the specified currency"
    
  property :currency,
    default: "USD",
    validate: ["USD", "EUR", "GBP", "CAD"],
    description: "ISO 4217 currency code"
end

# Step 1: Convert to JSON Schema and save to database
json_schema = OrderMessage.to_json_schema
connection.execute(
  "INSERT INTO message_schemas (class_name, schema_json) VALUES ($1, $2)",
  ["OrderMessage", json_schema.to_json]
)

# Step 2: Later, retrieve and reconstruct the class
stored_schema = connection.execute(
  "SELECT schema_json FROM message_schemas WHERE class_name = $1",
  ["OrderMessage"]
).first["schema_json"]

# Step 3: Dynamically create the class from JSON Schema
ReconstructedOrderMessage = SmartMessage::SchemaRegistry.from_json_schema(
  stored_schema
)

# Step 4: Use the reconstructed class
order = ReconstructedOrderMessage.new(
  order_id: "ORD-123",
  customer_email: "customer@example.com",
  amount: 99.99,
  currency: "USD"
)

# Verify it works
order.valid? # => true
order.publish # Works with configured transport/serializer
```

### Schema Storage Enhancement

The schema registry can store both the internal format and JSON Schema:

```ruby
def self.serialize_schema
  {
    class_name: name,
    class_version: version || 1,
    class_description: description,
    properties_schema: extract_properties_schema,
    validations_schema: extract_validations_schema,
    configuration_schema: extract_configuration_schema,
    json_schema: to_json_schema,  # Add JSON Schema representation
    
    # Metadata
    created_at: Time.current.iso8601,
    ruby_version: RUBY_VERSION,
    framework_version: SmartMessage::VERSION,
    
    # Schema fingerprinting
    schema_hash: calculate_schema_hash
  }
end
```

### Dynamic Schema Management Use Cases

With bidirectional JSON Schema conversion, applications gain powerful capabilities:

```ruby
# Save any message class to database
json = MyMessage.to_json_schema
DB.execute("INSERT INTO schemas (name, definition) VALUES (?, ?)", 
           [MyMessage.name, json.to_json])

# Later, recreate the class without the original Ruby code
stored_json = DB.execute("SELECT definition FROM schemas WHERE name = ?", 
                         ["MyMessage"]).first
MyMessage = SmartMessage.from_json_schema(stored_json)

# The recreated class is fully functional
msg = MyMessage.new(data: "test")
msg.publish
```

#### Key Capabilities Enabled

1. **Schema Marketplace**
```ruby
# Service A publishes its message schemas
OrderMessage.to_json_schema.tap do |schema|
  SchemaRegistry.publish(schema, visibility: :public)
end

# Service B discovers and uses them
available_schemas = SchemaRegistry.browse(tags: ["ecommerce"])
OrderMessage = SmartMessage.from_json_schema(available_schemas.first)
```

2. **Runtime Schema Updates**
```ruby
# Admin UI updates schema definition
updated_schema = modify_schema_via_ui(current_schema)
DB.execute("UPDATE schemas SET definition = ? WHERE name = ?", 
           [updated_schema.to_json, "OrderMessage"])

# Application reloads the class without restart
Object.send(:remove_const, :OrderMessage) if defined?(OrderMessage)
OrderMessage = SmartMessage.from_json_schema(updated_schema)
```

3. **Multi-Tenant Schemas**
```ruby
# Each tenant can have custom message schemas
tenant_schema = DB.execute(
  "SELECT definition FROM tenant_schemas WHERE tenant_id = ? AND name = ?",
  [tenant.id, "InvoiceMessage"]
).first

# Dynamically create tenant-specific class
tenant_class = SmartMessage.from_json_schema(
  tenant_schema,
  namespace: "Tenant#{tenant.id}".constantize
)
```

4. **Schema Versioning & Migration**
```ruby
# Store multiple versions
versions = DB.execute(
  "SELECT version, definition FROM schema_versions WHERE name = ? ORDER BY version",
  ["PaymentMessage"]
)

# Create version-specific classes
versions.each do |row|
  version_class = SmartMessage.from_json_schema(row['definition'])
  const_set("PaymentMessageV#{row['version']}", version_class)
end

# Handle messages from different versions
def process_payment(raw_message)
  version = raw_message['_sm_header']['version']
  handler = const_get("PaymentMessageV#{version}")
  handler.new(raw_message).process
end
```

5. **Schema-Driven Development**
```ruby
# Define schemas in a UI or configuration file
schema_config = YAML.load_file("message_schemas.yml")

# Generate all message classes at startup
schema_config.each do |name, definition|
  json_schema = build_json_schema(definition)
  const_set(name, SmartMessage.from_json_schema(json_schema))
end

# No Ruby message class files needed!
```

6. **Cross-Language Schema Sharing**
```ruby
# Export schemas for other languages
File.write("schemas/order_message.json", OrderMessage.to_json_schema.to_json)

# Python service can validate using standard JSON Schema
import jsonschema
schema = json.load(open("schemas/order_message.json"))
jsonschema.validate(message_data, schema)

# Then Ruby service can reconstruct the class
OrderMessage = SmartMessage.from_json_schema(
  File.read("schemas/order_message.json")
)
```

7. **A/B Testing Message Formats**
```ruby
# Store experimental schema variants
variants = {
  control: fetch_schema("OrderMessage", variant: "control"),
  test: fetch_schema("OrderMessage", variant: "test")
}

# Dynamically select variant
variant = ab_test.variant_for(user)
OrderMessage = SmartMessage.from_json_schema(variants[variant])
```

8. **Schema Compliance & Governance**
```ruby
# Central schema repository with approval workflow
pending_schema = SchemaApproval.find(id).schema_definition

# Preview the schema before approval
PreviewClass = SmartMessage.from_json_schema(pending_schema)
preview_msg = PreviewClass.new(sample_data)
validate_compliance(preview_msg)

# Once approved, deploy to production
if approved?
  ProductionMessage = SmartMessage.from_json_schema(pending_schema)
  cache_class(ProductionMessage)
end
```

This "code as data" approach fundamentally changes how message contracts are managed, enabling:
- **No-code schema management** via UIs
- **Runtime flexibility** without deployments
- **Schema portability** across services and languages
- **Centralized governance** with distributed execution
- **Version coexistence** without code duplication

### JSON Schema vs Ruby Marshal/DRb Comparison

Ruby provides built-in serialization via Marshal and distributed communication via DRb. Here's how the JSON Schema approach differs:

#### Ruby Marshal/DRb Approach

```ruby
# Marshal serializes Ruby objects including their class definition
class OrderMessage
  attr_accessor :order_id, :amount, :customer_email
  
  def initialize(order_id, amount, customer_email)
    @order_id = order_id
    @amount = amount
    @customer_email = customer_email
  end
end

# Serialize the entire object
order = OrderMessage.new("123", 99.99, "test@example.com")
serialized = Marshal.dump(order)

# Deserialize - requires the OrderMessage class to exist
restored = Marshal.load(serialized)  # Needs OrderMessage class loaded!

# DRb can share objects between Ruby processes
require 'drb/drb'
DRb.start_service("druby://localhost:8787", order)
```

#### JSON Schema Approach

```ruby
# Schema defines the structure, not the instance
schema = OrderMessage.to_json_schema  # Just the schema, not data

# Store schema separately from instances
DB.save_schema(schema)

# Later, recreate the class definition itself
OrderMessage = SmartMessage.from_json_schema(schema)

# Now create instances
order = OrderMessage.new(order_id: "123", amount: 99.99)
```

#### Key Differences

| Aspect | Marshal/DRb | JSON Schema |
|--------|------------|-------------|
| **What's Serialized** | Object instances with data | Class structure/definition |
| **Cross-Language** | Ruby only | Any language supporting JSON Schema |
| **Schema Evolution** | Breaks on class changes | Versions tracked explicitly |
| **Security** | Can execute arbitrary code | Safe, declarative only |
| **Storage Size** | Includes Ruby internals | Compact, standard JSON |
| **Validation** | None built-in | JSON Schema validation |
| **Documentation** | Not included | Descriptions embedded |
| **Human Readable** | Binary format | Plain JSON |
| **Class Required** | Must exist before deserializing | Creates class from schema |

#### When to Use Each

**Use Marshal/DRb when:**
- Working exclusively in Ruby ecosystem
- Need to serialize complex object graphs
- Want to preserve exact Ruby object state
- Building Ruby-only distributed systems
- Performance is critical (binary is faster)

**Use JSON Schema when:**
- Need cross-language compatibility
- Want human-readable, editable schemas
- Building microservices in multiple languages
- Need schema versioning and evolution
- Want to generate documentation
- Security is a concern (no code execution)
- Building schema management tools/UIs

#### Hybrid Approach

SmartMessage can actually use both:

```ruby
# Use JSON Schema for class definition
OrderMessage = SmartMessage.from_json_schema(stored_schema)

# Use Marshal for high-performance Ruby-to-Ruby communication
order = OrderMessage.new(data)
Marshal.dump(order)  # Fast binary serialization of instances

# Or use JSON for cross-language communication  
order.to_json  # Standard JSON for other languages

# Schema stays portable while instances can use optimal serialization
```

#### Security Consideration

```ruby
# Marshal can execute code - DANGEROUS with untrusted data
class EvilClass
  def marshal_load(data)
    system("rm -rf /")  # This would execute!
  end
end

Marshal.load(untrusted_data)  # Security risk!

# JSON Schema is safe - it's just data
SmartMessage.from_json_schema(untrusted_schema)  # Safe, no code execution
# Worst case: invalid schema that fails to create a working class
```

The JSON Schema approach is **better for**:
- Schema management and governance
- Cross-language systems
- API documentation
- Security-sensitive environments
- Long-term schema evolution

The Marshal/DRb approach is **better for**:
- Pure Ruby systems
- High-performance requirements  
- Complex object graphs
- Temporary serialization
- Ruby-specific features

They solve different problems: Marshal serializes **instances**, JSON Schema serializes **class definitions**

### Cross-Language Interoperability with JSON Schema

The JSON Schema approach enables true cross-language message contracts. Any language can consume SmartMessage schemas and generate equivalent message classes:

#### Rust Implementation

```rust
// Rust can generate structs from JSON Schema using schemars/serde
use serde::{Deserialize, Serialize};
use schemars::JsonSchema;
use serde_json::Value;
use validator::Validate;

// Generated from SmartMessage JSON Schema
#[derive(Debug, Serialize, Deserialize, JsonSchema, Validate)]
pub struct OrderMessage {
    #[serde(rename = "_sm_header")]
    pub sm_header: SmartMessageHeader,
    
    #[validate(length(min = 1))]
    pub order_id: String,
    
    #[validate(email)]
    pub customer_email: String,
    
    #[validate(range(min = 0.01))]
    pub amount: f64,
    
    #[serde(default = "default_currency")]
    #[validate(custom = "validate_currency")]
    pub currency: String,
    
    pub items: Vec<OrderItem>,
    
    pub created_at: chrono::DateTime<chrono::Utc>,
}

// Rust macro to generate from JSON Schema at compile time
use json_schema_to_rust::generate_struct;
generate_struct!("schemas/order_message.json");

// Or runtime generation using a schema loader
pub fn load_message_schema(schema_json: &str) -> Result<MessageType, Error> {
    let schema: Value = serde_json::from_str(schema_json)?;
    // Generate validation functions from schema
    let validator = JSONSchema::compile(&schema)?;
    
    MessageType::new(schema, validator)
}
```

#### Python Implementation

```python
# Python can use jsonschema and dataclasses
from dataclasses import dataclass, field
from typing import List, Optional
from datetime import datetime
import jsonschema
from dataclasses_jsonschema import JsonSchemaMixin

# Generate from SmartMessage JSON Schema
@dataclass
class OrderMessage(JsonSchemaMixin):
    """Generated from SmartMessage schema"""
    _sm_header: SmartMessageHeader
    order_id: str
    customer_email: str
    amount: float
    currency: str = "USD"
    items: List[OrderItem] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.now)
    
    def validate(self):
        schema = self.json_schema()
        jsonschema.validate(self.to_dict(), schema)
    
    @classmethod
    def from_json_schema(cls, schema_path: str):
        """Dynamically create class from JSON Schema"""
        with open(schema_path) as f:
            schema = json.load(f)
        
        # Use pydantic for dynamic model generation
        from pydantic import create_model
        return create_model(
            schema['title'],
            **parse_schema_properties(schema['properties'])
        )
```

#### TypeScript/JavaScript Implementation

```typescript
// TypeScript can generate interfaces from JSON Schema
import { FromSchema } from "json-schema-to-ts";
import Ajv from "ajv";

// Type generated from JSON Schema at compile time
type OrderMessage = FromSchema<typeof orderMessageSchema>;

// Or use json-schema-to-typescript for code generation
import { compile } from 'json-schema-to-typescript';

async function generateFromSmartMessage(schemaJson: string) {
  const ts = await compile(JSON.parse(schemaJson), 'OrderMessage');
  // Generates TypeScript interface code
}

// Runtime validation using the same schema
class SmartMessage<T> {
  private ajv = new Ajv();
  private validator: any;
  
  constructor(private schema: object) {
    this.validator = this.ajv.compile(schema);
  }
  
  create(data: unknown): T {
    if (!this.validator(data)) {
      throw new Error(this.validator.errors);
    }
    return data as T;
  }
}

// Use the SmartMessage schema directly
const OrderMessage = new SmartMessage<OrderMessageType>(
  await fetch('/schemas/order_message.json').then(r => r.json())
);
```

#### Go Implementation

```go
// Go can generate structs from JSON Schema
package messages

import (
    "github.com/xeipuuv/gojsonschema"
    "encoding/json"
)

// Generated from SmartMessage JSON Schema using go-jsonschema
type OrderMessage struct {
    SmHeader      SmartMessageHeader `json:"_sm_header"`
    OrderID       string            `json:"order_id" validate:"required"`
    CustomerEmail string            `json:"customer_email" validate:"required,email"`
    Amount        float64           `json:"amount" validate:"required,min=0.01"`
    Currency      string            `json:"currency" default:"USD"`
    Items         []OrderItem       `json:"items"`
    CreatedAt     time.Time         `json:"created_at"`
}

// Validate using the JSON Schema
func (m *OrderMessage) Validate() error {
    schemaLoader := gojsonschema.NewReferenceLoader("file://./schemas/order_message.json")
    documentLoader := gojsonschema.NewGoLoader(m)
    
    result, err := gojsonschema.Validate(schemaLoader, documentLoader)
    if err != nil {
        return err
    }
    
    if !result.Valid() {
        return fmt.Errorf("validation failed: %v", result.Errors())
    }
    return nil
}
```

#### Java Implementation

```java
// Java can use jsonschema2pojo or similar tools
import com.fasterxml.jackson.annotation.JsonProperty;
import javax.validation.constraints.*;
import com.networknt.schema.JsonSchema;
import com.networknt.schema.JsonSchemaFactory;

// Generated from SmartMessage JSON Schema
public class OrderMessage {
    @JsonProperty("_sm_header")
    private SmartMessageHeader smHeader;
    
    @NotBlank
    private String orderId;
    
    @NotBlank
    @Email
    private String customerEmail;
    
    @NotNull
    @DecimalMin("0.01")
    private BigDecimal amount;
    
    @Pattern(regexp = "USD|EUR|GBP|CAD")
    private String currency = "USD";
    
    private List<OrderItem> items;
    
    private Instant createdAt;
    
    // Validate against JSON Schema
    public void validate() throws ValidationException {
        JsonSchemaFactory factory = JsonSchemaFactory.getInstance();
        JsonSchema schema = factory.getSchema(
            getClass().getResourceAsStream("/schemas/order_message.json")
        );
        
        Set<ValidationMessage> errors = schema.validate(this.toJson());
        if (!errors.isEmpty()) {
            throw new ValidationException(errors.toString());
        }
    }
}
```

#### Shared Schema Registry

```yaml
# All services can share schemas via a central registry
services:
  ruby_service:
    language: ruby
    schema_fetch: |
      schema = fetch_schema("OrderMessage")
      OrderMessage = SmartMessage.from_json_schema(schema)
      
  rust_service:
    language: rust
    schema_fetch: |
      let schema = fetch_schema("OrderMessage")?;
      generate_struct!(schema);
      
  python_service:
    language: python
    schema_fetch: |
      schema = fetch_schema("OrderMessage")
      OrderMessage = create_model_from_schema(schema)
      
  node_service:
    language: typescript
    schema_fetch: |
      const schema = await fetchSchema("OrderMessage");
      const OrderMessage = new SmartMessage(schema);
```

#### Key Cross-Language Benefits

1. **Single Source of Truth**: One schema defines the contract for all languages
2. **Automatic Code Generation**: Most languages have JSON Schema → code generators
3. **Consistent Validation**: All services validate messages the same way
4. **Type Safety**: Strongly-typed languages get compile-time checking
5. **Documentation**: Schema includes descriptions for all languages
6. **Evolution Tracking**: Version changes are visible to all services
7. **No Manual Sync**: Changes propagate automatically through the schema

#### Example: Polyglot Microservices

```ruby
# Ruby service publishes schema
OrderMessage.to_json_schema.tap do |schema|
  Redis.set("schema:OrderMessage:v2", schema.to_json)
  AMQP.publish("schema.updated", {name: "OrderMessage", version: 2})
end

# Rust service receives update and regenerates
let schema_json = redis.get("schema:OrderMessage:v2")?;
rebuild_message_types(schema_json);

# Python service validates incoming message
schema = redis.get("schema:OrderMessage:v2")
validator = Draft7Validator(json.loads(schema))
validator.validate(incoming_message)

# All services stay in sync automatically!
```

This enables true **polyglot microservices** where:
- Ruby defines the canonical message schema
- Rust gets memory-safe, zero-cost abstractions
- Python gets dynamic typing with validation
- TypeScript gets compile-time type checking
- Go gets efficient JSON marshaling
- Java gets enterprise integration

All from the same SmartMessage JSON Schema!

### Implementation Roadmap

To implement this schema registry system:

1. **Phase 1: Core Schema Generation**
   - Add `to_json_schema` method to SmartMessage::Base
   - Include property descriptions and validations
   - Map Ruby types to JSON Schema types
   - Generate standard-compliant JSON Schema documents

2. **Phase 2: Schema Persistence**
   - Create database table for schema storage
   - Implement automatic registration hooks
   - Add schema versioning and evolution tracking
   - Store both internal format and JSON Schema

3. **Phase 3: Dynamic Class Creation**
   - Implement `from_json_schema` method
   - Support validation reconstruction from JSON Schema
   - Enable round-trip conversion (Ruby → JSON Schema → Ruby)
   - Preserve transport and serializer configuration

4. **Phase 4: Cross-Language Support**
   - Document schema consumption patterns for each language
   - Create example implementations for Rust, Python, TypeScript, Go, Java
   - Build shared schema registry for polyglot services
   - Enable automatic schema synchronization

5. **Phase 5: Advanced Features**
   - Schema marketplace for sharing between services
   - Runtime schema updates without deployment
   - Multi-tenant schema support
   - A/B testing of message formats
   - Schema compliance and governance tools

### Summary

The SmartMessage Schema Registry transforms message definitions from static code into dynamic, manageable data. By leveraging JSON Schema as a universal contract language, it enables:

- **Code as Data**: Message schemas become first-class data entities that can be stored, versioned, and managed independently of application code
- **Polyglot Interoperability**: Any language can consume and implement SmartMessage contracts through standard JSON Schema
- **Runtime Flexibility**: Classes can be created, updated, and versioned without code deployment
- **Schema Governance**: Central management with distributed execution across services
- **Zero-Code Development**: Business users can define message schemas through UIs without writing Ruby code

This approach fundamentally shifts how distributed systems manage message contracts, providing the flexibility of dynamic languages with the safety of schema validation, all while maintaining cross-language compatibility through industry-standard JSON Schema.

### Benefits

1. **Automatic Registration**: Schemas are captured automatically when classes load
2. **Schema Evolution**: Track how message formats change over time  
3. **Change Detection**: SHA256 hashing detects any schema modifications
4. **Audit Trail**: Complete history of all message schemas for compliance
5. **Version Management**: Track parent-child relationships between versions
6. **Environment Tracking**: Know which schemas are used in which environments
7. **Performance**: Indexed for fast lookups and discovery operations
8. **JSON Schema Export**: Standard format for cross-platform compatibility
9. **Rich Documentation**: Descriptions at message and property levels
10. **Dynamic Class Creation**: Rebuild Ruby classes from stored schemas
11. **Cross-Language Support**: Generate equivalent classes in any language
12. **Runtime Updates**: Modify schemas without redeploying code
13. **Schema Marketplace**: Share and discover schemas across services
14. **Security**: Safe schema sharing without code execution risks
15. **Governance**: Centralized schema management with approval workflows