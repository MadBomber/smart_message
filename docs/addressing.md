# Entity Addressing

SmartMessage supports entity-to-entity addressing through built-in FROM/TO/REPLY_TO fields in message headers. This enables sophisticated messaging patterns including point-to-point communication, broadcast messaging, and request-reply workflows.

## Overview

Entity addressing in SmartMessage provides:

- **Sender Identification**: Required `from` field identifies the sending entity
- **Recipient Targeting**: Optional `to` field for point-to-point messaging  
- **Response Routing**: Optional `reply_to` field for request-reply patterns
- **Broadcast Support**: Omitting `to` field enables broadcast to all subscribers
- **Dual-Level Configuration**: Class and instance-level addressing configuration

## Address Fields

### FROM (Required)
The `from` field identifies the entity sending the message. This is required for all messages.

```ruby
class MyMessage < SmartMessage::Base
  from 'order-service'  # Required sender identity
  
  property :data
end
```

### TO (Optional)
The `to` field specifies the intended recipient entity. When present, creates point-to-point messaging. When `nil`, the message is broadcast to all subscribers.

```ruby
# Point-to-point messaging
class DirectMessage < SmartMessage::Base
  from 'sender-service'
  to 'recipient-service'  # Specific target
  
  property :content
end

# Broadcast messaging
class AnnouncementMessage < SmartMessage::Base
  from 'admin-service'
  # No 'to' field = broadcast to all subscribers
  
  property :announcement
end
```

### REPLY_TO (Optional)
The `reply_to` field specifies where responses should be sent. Defaults to the `from` entity if not specified.

```ruby
class RequestMessage < SmartMessage::Base
  from 'client-service'
  to 'api-service'
  reply_to 'client-callback-service'  # Responses go here
  
  property :request_data
end
```

## Configuration Patterns

### Class-Level Configuration

Set default addressing for all instances of a message class:

```ruby
class PaymentMessage < SmartMessage::Base
  version 1
  
  # Class-level addressing
  from 'payment-service'
  to 'bank-gateway'
  reply_to 'payment-service'
  
  property :amount, required: true
  property :account_id, required: true
end

# All instances inherit class addressing
payment = PaymentMessage.new(amount: 100.00, account_id: "ACCT-123")
puts payment._sm_header.from     # => 'payment-service'
puts payment._sm_header.to       # => 'bank-gateway'
puts payment._sm_header.reply_to # => 'payment-service'
```

### Instance-Level Overrides

Override addressing for specific message instances:

```ruby
class FlexibleMessage < SmartMessage::Base
  from 'service-a'
  to 'service-b'
  
  property :data
end

# Override addressing for this instance
message = FlexibleMessage.new(data: "test")
message.from('different-sender')
message.to('different-recipient')
message.reply_to('different-reply-service')

puts message.from     # => 'different-sender'
puts message.to       # => 'different-recipient' 
puts message.reply_to # => 'different-reply-service'

# Class defaults remain unchanged
puts FlexibleMessage.from # => 'service-a'
puts FlexibleMessage.to   # => 'service-b'
```

## Messaging Patterns

### Point-to-Point Messaging

Direct communication between two specific entities:

```ruby
class OrderProcessingMessage < SmartMessage::Base
  from 'order-service'
  to 'inventory-service'  # Direct target
  reply_to 'order-service'
  
  property :order_id, required: true
  property :items, required: true
end

# Message goes directly to inventory-service
order = OrderProcessingMessage.new(
  order_id: "ORD-123", 
  items: ["widget-1", "widget-2"]
)
order.publish  # Only inventory-service receives this
```

### Broadcast Messaging

Send message to all subscribers by omitting the `to` field:

```ruby
class SystemMaintenanceMessage < SmartMessage::Base
  from 'admin-service'
  # No 'to' field = broadcast
  
  property :message, required: true
  property :scheduled_time, required: true
end

# Message goes to all subscribers
maintenance = SystemMaintenanceMessage.new(
  message: "System maintenance tonight at 2 AM",
  scheduled_time: Time.parse("2024-01-15 02:00:00")
)
maintenance.publish  # All subscribers receive this
```

### Request-Reply Pattern

Structured request-response communication:

```ruby
# Request message
class UserLookupRequest < SmartMessage::Base
  from 'web-service'
  to 'user-service'
  reply_to 'web-service'  # Responses come back here
  
  property :user_id, required: true
  property :request_id, required: true  # For correlation
end

# Response message  
class UserLookupResponse < SmartMessage::Base
  from 'user-service'
  # 'to' will be set to the original 'reply_to' value
  
  property :user_id, required: true
  property :request_id, required: true  # Correlation ID
  property :user_data
  property :success, default: true
end

# Send request
request = UserLookupRequest.new(
  user_id: "USER-123",
  request_id: SecureRandom.uuid
)
request.publish

# In user-service handler:
class UserLookupRequest
  def self.process(header, payload)
    request_data = JSON.parse(payload)
    
    # Process lookup...
    user_data = UserService.find(request_data['user_id'])
    
    # Send response back to reply_to address
    response = UserLookupResponse.new(
      user_id: request_data['user_id'],
      request_id: request_data['request_id'],
      user_data: user_data
    )
    response.to(header.reply_to)  # Send to original reply_to
    response.publish
  end
end
```

### Gateway Pattern

Forward messages between different transports/formats:

```ruby
class GatewayMessage < SmartMessage::Base
  from 'gateway-service'
  
  property :original_message
  property :source_format
  property :target_format
end

# Receive from one transport/format
incoming = SomeMessage.new(data: "from system A")

# Forward to different system with different addressing
gateway_msg = GatewayMessage.new(
  original_message: incoming.to_h,
  source_format: 'json',
  target_format: 'xml'
)

# Override transport and addressing for forwarding
gateway_msg.config do
  transport DifferentTransport.new
  serializer DifferentSerializer.new
end
gateway_msg.to('system-b')
gateway_msg.publish
```

## Address Validation

The `from` field is required and validated automatically:

```ruby
class InvalidMessage < SmartMessage::Base
  # No 'from' specified - will fail validation
  property :data
end

message = InvalidMessage.new(data: "test")
message.publish  # Raises SmartMessage::Errors::ValidationError
# => "The property 'from' From entity ID is required for message routing and replies"
```

## Header Access

Access addressing information from message headers:

```ruby
class SampleMessage < SmartMessage::Base
  from 'sample-service'
  to 'target-service'
  reply_to 'callback-service'
  
  property :content
end

message = SampleMessage.new(content: "Hello")
header = message._sm_header

puts header.from      # => 'sample-service'
puts header.to        # => 'target-service'  
puts header.reply_to  # => 'callback-service'
puts header.uuid      # => Generated UUID
puts header.message_class  # => 'SampleMessage'
```

## Integration with Dispatcher

The dispatcher can use addressing metadata for advanced routing logic:

```ruby
# Future enhancement: Dispatcher filtering by recipient
# dispatcher.route(message_header, payload) do |header|
#   if header.to.nil?
#     # Broadcast to all subscribers
#     route_to_all_subscribers(header.message_class)
#   else
#     # Route only to specific recipient
#     route_to_entity(header.to, header.message_class)
#   end
# end
```

## Best Practices

### Entity Naming
Use consistent, descriptive entity identifiers:

```ruby
# Good: Descriptive service names
from 'order-management-service'
to 'inventory-tracking-service'
reply_to 'order-status-service'

# Avoid: Generic or unclear names
from 'service1'
to 'app'
```

### Address Consistency
Maintain consistent addressing patterns across your application:

```ruby
# Consistent pattern for microservices
class OrderMessage < SmartMessage::Base
  from 'order-service'
  to 'fulfillment-service'
  reply_to 'order-service'
end

class PaymentMessage < SmartMessage::Base  
  from 'payment-service'
  to 'billing-service'
  reply_to 'payment-service'
end
```

### Gateway Configuration
For gateway patterns, use instance-level overrides:

```ruby
# Class defines default routing
class APIMessage < SmartMessage::Base
  from 'api-gateway'
  to 'internal-service'
end

# Override for external routing
message = APIMessage.new(data: "external request")
message.to('external-partner-service')
message.config do
  transport ExternalTransport.new
  serializer SecureSerializer.new
end
message.publish
```

## Future Enhancements

The addressing system provides the foundation for advanced features:

- **Dispatcher Filtering**: Route messages based on recipient targeting
- **Security Integration**: Entity-based authentication and authorization
- **Audit Trails**: Track message flow between entities
- **Load Balancing**: Distribute messages across entity instances
- **Circuit Breakers**: Per-entity failure handling

Entity addressing enables sophisticated messaging architectures while maintaining the simplicity and flexibility that makes SmartMessage powerful.