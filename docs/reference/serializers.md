# Serializers

Serializers handle the encoding and decoding of message content, transforming Ruby objects into wire formats suitable for transmission and storage.

## Overview

Serializers are responsible for:
- **Encoding**: Converting SmartMessage instances to transmittable formats
- **Decoding**: Converting received data back to Ruby objects
- **Format Support**: Handling different data formats (JSON, XML, MessagePack, etc.)
- **Type Safety**: Ensuring data integrity during conversion

## Built-in Serializers

### JSON Serializer

The default serializer that converts messages to/from JSON format.

**Features:**
- Human-readable output
- Wide compatibility 
- Built on Ruby's standard JSON library
- Automatic property serialization

**Usage:**

```ruby
# Basic usage
serializer = SmartMessage::Serializer::Json.new

# Configure in message class
class UserMessage < SmartMessage::Base
  property :user_id
  property :email
  property :preferences
  
  config do
    serializer SmartMessage::Serializer::Json.new
  end
end

# Manual encoding/decoding
message = UserMessage.new(user_id: 123, email: "user@example.com")
encoded = serializer.encode(message)
# => '{"user_id":123,"email":"user@example.com","preferences":null}'
```

**Encoding Behavior:**
- All defined properties are included
- Nil values are preserved
- Internal `_sm_` properties are included in serialization
- Uses Ruby's `#to_json` method under the hood

## Serializer Interface

All serializers must implement the `SmartMessage::Serializer::Base` interface:

### Required Methods

```ruby
class CustomSerializer < SmartMessage::Serializer::Base
  def initialize(options = {})
    @options = options
    # Custom initialization
  end
  
  # Convert SmartMessage instance to wire format
  def encode(message_instance)
    # Transform message_instance to your format
    # Return string or binary data
  end
  
  # Convert wire format back to hash
  def decode(payload)
    # Transform payload string back to hash
    # Return hash suitable for SmartMessage.new(hash)
  end
end
```

### Example: MessagePack Serializer

```ruby
require 'msgpack'

class MessagePackSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    message_instance.to_h.to_msgpack
  end
  
  def decode(payload)
    MessagePack.unpack(payload)
  end
end

# Usage
class BinaryMessage < SmartMessage::Base
  property :data
  property :timestamp
  
  config do
    serializer MessagePackSerializer.new
  end
end
```

### Example: XML Serializer

```ruby
require 'nokogiri'

class XMLSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    data = message_instance.to_h
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.message do
        data.each do |key, value|
          xml.send(key, value)
        end
      end
    end
    builder.to_xml
  end
  
  def decode(payload)
    doc = Nokogiri::XML(payload)
    hash = {}
    doc.xpath('//message/*').each do |node|
      hash[node.name] = node.text
    end
    hash
  end
end
```

## Serialization Patterns

### Type Coercion

Handle type conversions during serialization:

```ruby
class TypedSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    data = message_instance.to_h
    
    # Convert specific types
    data.transform_values do |value|
      case value
      when Time
        value.iso8601
      when Date
        value.to_s
      when BigDecimal
        value.to_f
      else
        value
      end
    end.to_json
  end
  
  def decode(payload)
    data = JSON.parse(payload)
    
    # Convert back from strings
    data.transform_values do |value|
      case value
      when /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
        Time.parse(value)
      else
        value
      end
    end
  end
end
```

### Nested Object Serialization

Handle complex nested structures:

```ruby
class NestedSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    data = deep_serialize(message_instance.to_h)
    JSON.generate(data)
  end
  
  def decode(payload)
    data = JSON.parse(payload)
    deep_deserialize(data)
  end
  
  private
  
  def deep_serialize(obj)
    case obj
    when Hash
      obj.transform_values { |v| deep_serialize(v) }
    when Array
      obj.map { |v| deep_serialize(v) }
    when SmartMessage::Base
      # Serialize nested messages
      obj.to_h
    else
      obj
    end
  end
  
  def deep_deserialize(obj)
    case obj
    when Hash
      obj.transform_values { |v| deep_deserialize(v) }
    when Array
      obj.map { |v| deep_deserialize(v) }
    else
      obj
    end
  end
end
```

## Serialization Options

### Configurable Serializers

```ruby
class ConfigurableJSONSerializer < SmartMessage::Serializer::Base
  def initialize(options = {})
    @pretty = options[:pretty] || false
    @exclude_nil = options[:exclude_nil] || false
    @date_format = options[:date_format] || :iso8601
  end
  
  def encode(message_instance)
    data = message_instance.to_h
    
    # Remove nil values if requested
    data = data.compact if @exclude_nil
    
    # Format dates
    data = format_dates(data)
    
    # Generate JSON
    if @pretty
      JSON.pretty_generate(data)
    else
      JSON.generate(data)
    end
  end
  
  private
  
  def format_dates(data)
    data.transform_values do |value|
      case value
      when Time, Date
        case @date_format
        when :iso8601
          value.iso8601
        when :unix
          value.to_i
        when :rfc2822
          value.rfc2822
        else
          value.to_s
        end
      else
        value
      end
    end
  end
end

# Usage with options
class TimestampMessage < SmartMessage::Base
  property :event
  property :timestamp
  
  config do
    serializer ConfigurableJSONSerializer.new(
      pretty: true,
      exclude_nil: true,
      date_format: :unix
    )
  end
end
```

## Error Handling

### Serialization Errors

Handle encoding/decoding failures gracefully:

```ruby
class SafeSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    JSON.generate(message_instance.to_h)
  rescue JSON::GeneratorError => e
    # Log the error
    puts "Serialization failed: #{e.message}"
    
    # Fallback to simple string representation
    message_instance.to_h.to_s
  end
  
  def decode(payload)
    JSON.parse(payload)
  rescue JSON::ParserError => e
    # Log the error
    puts "Deserialization failed: #{e.message}"
    
    # Return error indicator or empty hash
    { "_error" => "Failed to deserialize: #{e.message}" }
  end
end
```

### Validation During Serialization

```ruby
class ValidatingSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    validate_before_encoding(message_instance)
    JSON.generate(message_instance.to_h)
  end
  
  def decode(payload)
    data = JSON.parse(payload)
    validate_after_decoding(data)
    data
  end
  
  private
  
  def validate_before_encoding(message)
    required_fields = message.class.properties.select do |prop|
      message.class.required?(prop)
    end
    
    missing = required_fields.select { |field| message[field].nil? }
    
    if missing.any?
      raise "Missing required fields: #{missing.join(', ')}"
    end
  end
  
  def validate_after_decoding(data)
    unless data.is_a?(Hash)
      raise "Expected hash, got #{data.class}"
    end
    
    # Additional validation logic
  end
end
```

## Performance Considerations

### Binary Serialization

For high-performance scenarios, consider binary formats:

```ruby
class ProtobufSerializer < SmartMessage::Serializer::Base
  def initialize(proto_class)
    @proto_class = proto_class
  end
  
  def encode(message_instance)
    proto_obj = @proto_class.new(message_instance.to_h)
    proto_obj.serialize_to_string
  end
  
  def decode(payload)
    proto_obj = @proto_class.parse(payload)
    proto_obj.to_h
  end
end

# Usage
UserProto = Google::Protobuf::DescriptorPool.generated_pool.lookup("User").msgclass

class UserMessage < SmartMessage::Base
  property :user_id
  property :name
  
  config do
    serializer ProtobufSerializer.new(UserProto)
  end
end
```

### Streaming Serialization

For large messages, consider streaming:

```ruby
class StreamingSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    StringIO.new.tap do |io|
      JSON.dump(message_instance.to_h, io)
    end.string
  end
  
  def decode(payload)
    StringIO.new(payload).tap do |io|
      JSON.load(io)
    end
  end
end
```

## Compression Support

### Compressed Serialization

```ruby
class CompressedJSONSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    json_data = JSON.generate(message_instance.to_h)
    Zlib::Deflate.deflate(json_data)
  end
  
  def decode(payload)
    json_data = Zlib::Inflate.inflate(payload)
    JSON.parse(json_data)
  end
end

# Usage for large messages
class LargeDataMessage < SmartMessage::Base
  property :dataset
  property :metadata
  
  config do
    serializer CompressedJSONSerializer.new
  end
end
```

## Testing Serializers

### Serializer Testing Patterns

```ruby
RSpec.describe CustomSerializer do
  let(:serializer) { CustomSerializer.new }
  let(:message) do
    TestMessage.new(
      user_id: 123,
      email: "test@example.com",
      created_at: Time.parse("2025-08-17T10:30:00Z")
    )
  end
  
  describe "#encode" do
    it "produces valid output" do
      result = serializer.encode(message)
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
    
    it "includes all properties" do
      result = serializer.encode(message)
      # Format-specific assertions
    end
  end
  
  describe "#decode" do
    it "roundtrips correctly" do
      encoded = serializer.encode(message)
      decoded = serializer.decode(encoded)
      
      expect(decoded["user_id"]).to eq(123)
      expect(decoded["email"]).to eq("test@example.com")
    end
  end
  
  describe "error handling" do
    it "handles invalid input gracefully" do
      expect { serializer.decode("invalid") }.not_to raise_error
    end
  end
end
```

### Mock Serializer for Testing

```ruby
class MockSerializer < SmartMessage::Serializer::Base
  attr_reader :encoded_messages, :decoded_payloads
  
  def initialize
    @encoded_messages = []
    @decoded_payloads = []
  end
  
  def encode(message_instance)
    @encoded_messages << message_instance
    "mock_encoded_#{message_instance.object_id}"
  end
  
  def decode(payload)
    @decoded_payloads << payload
    { "mock" => "decoded", "payload" => payload }
  end
  
  def clear
    @encoded_messages.clear
    @decoded_payloads.clear
  end
end
```

## Common Serialization Issues

### Handling Special Values

```ruby
class RobustJSONSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    data = sanitize_for_json(message_instance.to_h)
    JSON.generate(data)
  end
  
  private
  
  def sanitize_for_json(obj)
    case obj
    when Hash
      obj.transform_values { |v| sanitize_for_json(v) }
    when Array
      obj.map { |v| sanitize_for_json(v) }
    when Float
      return nil if obj.nan? || obj.infinite?
      obj
    when BigDecimal
      obj.to_f
    when Symbol
      obj.to_s
    when Complex, Rational
      obj.to_f
    else
      obj
    end
  end
end
```

### Character Encoding

```ruby
class EncodingAwareSerializer < SmartMessage::Serializer::Base
  def encode(message_instance)
    data = message_instance.to_h
    json = JSON.generate(data)
    json.force_encoding('UTF-8')
  end
  
  def decode(payload)
    # Ensure proper encoding
    payload = payload.force_encoding('UTF-8')
    JSON.parse(payload)
  end
end
```

## Next Steps

- [Custom Serializers](custom-serializers.md) - Build your own serializer
- [Transports](transports.md) - How serializers work with transports
- [Message Headers](headers.md) - Understanding message metadata
- [Examples](examples.md) - Real-world serialization patterns